enablePlugins(ScalaJSPlugin)

name := "Ensime scala.js"

scalaVersion := "2.11.5"

scalaJSStage in Global := FastOptStage

target := baseDirectory.value / "lib" / "scalajs"

libraryDependencies ++= Seq(
    "org.scala-js" %%% "scalajs-dom" % "0.8.0"
)

scalacOptions ++= Seq("-unchecked", "-deprecation", "-feature", "-language:postfixOps", "-language:dynamics")
