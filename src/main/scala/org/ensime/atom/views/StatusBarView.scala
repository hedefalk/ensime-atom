// {View} = require 'atom-space-pen-views'
//
// # View for the little status messages down there where messages from Ensime server can be shown
// module.exports =
//   class StatusbarView extends View
//     @content: ->
//       @div class: 'ensime-status inline-block'
//
//     initialize: ->
//
//     serialize: ->
//
//     init: ->
//       @attach()
//
//     attach: =>
//       statusbar = document.querySelector('status-bar')
//       statusbar?.addLeftTile {item: this}
//
//     setText: (text) =>
//       @text("Ensime: #{text}").show()
//
//     destroy: ->
//       @detach()

package org.ensime.atom.views

import scala.scalajs.js

private[views] object SpacePen {
  private val spacePenViews = js.Dynamic.global.require("atom-space-pen-views")
  type View = spacePenViews.view
}

class StatusBarView extends SpacePen.View  {
  override def content =
    super.div()

}
