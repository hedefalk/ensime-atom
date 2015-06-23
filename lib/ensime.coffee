net = require('net')
exec = require('child_process').exec
fs = require 'fs'
path = require('path')
{Subscriber} = require 'emissary'
SwankClient = require './swank-client'
StatusbarView = require './statusbar-view'
{CompositeDisposable} = require 'atom'
{car, cdr, fromLisp} = require './lisp'
EditorControl = require './editor-control'
ShowTypes = require './show-types'
{updateEnsimeServer, startEnsimeServer, classpathFileName} = require './ensime-startup'
TypeCheckingFeature = require('./features/typechecking')
{log, modalMsg, isScalaSource, projectPath} = require './utils'


portFile = ->
    loadSettings = atom.getLoadSettings()
    projectPath() + '/.ensime_cache/port'


createSwankClient = (portFileLoc, generalHandler) ->
  port = fs.readFileSync(portFileLoc).toString()
  new SwankClient(port, generalHandler)


module.exports = Ensime =
  subscriptions: null

  config: {
    ensimeServerVersion: {
      description: 'Version of Ensime server',
      type: 'string',
      default: "0.9.10-SNAPSHOT"
    },
    sbtExec: {
      description: "Full path to sbt. 'which sbt'",
      type: 'string',
      default: "/usr/local/bin/sbt"
    },
    JAVA_HOME: {
      description: 'path to JAVA_HOME',
      type: 'string',
      default: '/Library/Java/JavaVirtualMachines/jdk1.8.0_05.jdk/Contents/Home/'
    },
    ensimeServerFlags: {
      description: 'java flags for ensime server startup',
      type: 'string',
      default: ''
    },
    devMode: {
      description: 'Turn on for extra console logging during development',
      type: 'boolean',
      default: false
    },
    runServerDetached: {
      description: "Run the Ensime server as a detached process. Useful while developing",
      type: 'boolean',
      default: false
    }
    typecheckWhen: {
      description: "When to typecheck",
      type: 'string',
      default: 'typing',
      enum: ['command', 'save', 'typing']
    }
    typecheckTypingDelay: {
      description: "Delay for typechecking while typing, in milliseconds. Too low might cause performance issues."
      type: 'integer'
      default: '500'
    }
  }


  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @editorControllers = new WeakMap
    @showTypesControllers = new WeakMap

    # Need to have a started server and port file
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:update-ensime-server", => updateEnsimeServer()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:start", => @initProject()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:stop", => @stopEnsime()

    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-all", => @typecheckAll()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-file", => @typecheckFile()
    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:typecheck-buffer", => @typecheckBuffer()

    @subscriptions.add atom.commands.add 'atom-workspace', "ensime:go-to-definition", => @goToDefinitionOfCursor()

    # https://discuss.atom.io/t/ok-to-use-grammar-cson-for-just-file-assoc/17801/11
    Promise.resolve(
      atom.packages.isPackageLoaded('language-scala') && atom.packages.activatePackage('language-scala')
    ).then (languageScalaPkg) ->
      if languageScalaPkg
        # language-scala is loaded and activated
      else
        # language-scala is not loaded
        grammar = atom.packages.resolvePackagePath('Ensime') + path.sep + 'grammars-hidden' + path.sep + 'scala.cson'
        atom.grammars.loadGrammar grammar

  deactivate: ->
    @subscriptions.dispose()
    @controlSubscription.dispose()
    if not atom.config.get('Ensime.runServerDetached')
      @ensimeServerPid?.kill()
    @deleteControllers()

  serialize: ->

  maybeStartEnsimeServer: ->
    if not @ensimeServerPid
      if fs.existsSync(portFile())
        modalMsg(".ensime/cache/port file already exists. Sure no running server already? If so, remove file and try again.")
      else
        startEnsimeServer((pid) =>
          @ensimeServerPid = pid
          @ensimeServerPid.on 'exit', (code) =>
            @ensimeServerPid = null
        )
    else
      modalMsg("Already running", "Ensime server process already running")

  generalHandler: (msg) ->
    head = car(msg)
    tail = cdr(msg)
    headStr = head.toString()
    console.log("this: " + this)

    if(headStr == ':compiler-ready')
      @statusbarView.setText('compiler ready…')

    else if(headStr == ':full-typecheck-finished')
      @statusbarView.setText('Full typecheck finished!')

    else if(headStr == ':indexer-ready')
      @statusbarView.setText('indexer ready')

    else if(headStr.startsWith(':background-message'))
      @statusbarView.setText("#{tail}")

    else if(headStr == ':scala-notes')
      @typechecking.addScalaNotes(tail)

    else if(headStr == ':clear-all-scala-notes')
      @typechecking.clearScalaNotes()




  initProject: ->
    @typechecking = new TypeCheckingFeature()

    initClient = =>

      @client = createSwankClient(portFile(), (msg) => @generalHandler(msg) )


      @statusbarView = new StatusbarView()
      @statusbarView.init()

      @client.post("(swank:init-project)", (msg) -> )

      @controlSubscription = atom.workspace.observeTextEditors (editor) =>
        if not @editorControllers.get(editor) && isScalaSource(editor)
          @editorControllers.set(editor, new EditorControl(editor, @client))
          @showTypesControllers.set(editor, new ShowTypes(editor, @client))

          @subscriptions.add editor.onDidDestroy () =>
            @removeControllers editor

    # Startup server
    if not fs.existsSync(portFile())
      @maybeStartEnsimeServer()

    # Client
    tryStartup = (trysLeft) =>
      if(trysLeft == 0)
        modalMsg("Server doesn't seem to startup in time. Report bug!")
      else if fs.existsSync(portFile())
        initClient()
      else
        @clientStartupTimeout = setTimeout (=>
          tryStartup(trysLeft - 1)
        ), 500

    if(fs.existsSync(classpathFileName()))
      tryStartup(20) # 10 sec should be enough?
    else
      tryStartup(200)

  removeControllers: (editor) ->
    @showTypesControllers.get(editor)?.deactivate()
    @showTypesControllers.delete(editor)
    @editorControllers.get(editor)?.deactivate()
    @editorControllers.delete(editor)

  deleteControllers: ->
    for editor in atom.workspace.getTextEditors()
      @removeControllers editor


  stopEnsime: ->
    @ensimeServerPid?.kill()
    @ensimeServerPid = null



    @statusbarView?.destroy()
    @statusbarView = null

    @deleteControllers()

    @client?.destroy()
    @client = null


    @typechecking?.destroy()
    @typechecking = null



    #atom.packages.deactivatePackage('Ensime')



  typecheckAll: ->
    @client.post("(swank:typecheck-all)", (msg) ->)

  # typechecks currently open file
  typecheckBuffer: ->
    b = atom.workspace.getActiveTextEditor()?.getBuffer()
    @client.typecheckBuffer(b)

  typecheckFile: ->
    b = atom.workspace.getActiveTextEditor()?.getBuffer()
    @client.typecheckFile(b)

  goToDefinitionOfCursor: ->
    editor = atom.workspace.getActiveTextEditor()
    textBuffer = editor.getBuffer()
    pos = editor.getCursorBufferPosition()
    @client.goToTypeAtPoint(textBuffer, pos)



  provideLinks: ->
    Processor = require('./provide-links-processor')
    new Processor( {getClient: => @client})

  provideAutocomplete: ->
    log('provideAutocomplete called')
    getClient = =>
      log('getClient called and this is ' + this + ", @client is " + @client)
      @client

    {
      selector: '.source.scala'
      disableForSelector: '.source.scala .comment'

      getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) =>
        if(getClient())
          new Promise (resolve) =>
            log('ensime.getSuggestions')
            getClient().getCompletions(editor.getBuffer(), bufferPosition, resolve)
        else
          log('@client undefined')
          []
    }
