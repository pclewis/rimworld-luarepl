local UI              = require("Verse.UI")
local GUI             = require("UnityEngine.GUI")
local GUIStyle        = require("UnityEngine.GUIStyle")
local GUIContent      = require("UnityEngine.GUIContent")
local Event           = require("UnityEngine.Event")
local EventType       = require("UnityEngine.EventType")
local KeyCode         = require("UnityEngine.KeyCode")
local Widgets         = require("Verse.Widgets")
local Log             = require("Verse.Log")
local Text            = require("Verse.Text")
local TextAnchor      = require("UnityEngine.TextAnchor")
local Color           = require("UnityEngine.Color")
local GameFont        = require("Verse.GameFont")
local Find            = require("Verse.Find")
local Vector2         = require("UnityEngine.Vector2")
local Rect            = require("UnityEngine.Rect")
local HarmonyInstance = require("Harmony.HarmonyInstance")
local HarmonyMethod   = require("Harmony.HarmonyMethod")

local _
local gui = {}
local MainTabWindow_LuaREPL = {}

local harmony = HarmonyInstance.Create("luarepl")

local state = { output       = {}
              , outputLength = 0
              , outputHeight = 0
              , inputBuffer  = ""
              , outputScrollPosition = Vector2.__new()
              , inputHistory = {}
              , stashedInput = ""
              , historyIndex = -1
              , logMessageQueue = {} }


function gui.patchLogMessage()
  local patchClass =
    class('LuaTest.LogMessageQueuePatch3', typeof(require('System.Object')),
          {postfix=function(msg) state.logMessageQueue[#state.logMessageQueue+1] = msg.text end},
          function(typeBuilder)
            local method = typeBuilder.AddStaticMethod('postfix', typeof(require('System.Void')), { typeof(require('Verse.LogMessage')) }, 'postfix')
            method.DefineParameter(1,0,"msg")
          end
    )
  local original = typeof(require('Verse.LogMessageQueue')).GetMethod("Enqueue")
  local postfix = patchClass.GetMethod("postfix")
  harmony.Patch(original, nil, HarmonyMethod.__new(postfix))
end

gui.patchLogMessage()

local bufferWidth  = 0
local bufferHeight = 0

local defaultTextStyle = GUIStyle.__new(Text.fontStyles[0])
defaultTextStyle.alignment = TextAnchor.MiddleLeft

local defaultErrorStyle = GUIStyle.__new(defaultTextStyle)
defaultErrorStyle.normal.textColor = Color.red

function MainTabWindow_LuaREPL:DoWindowContents(inRect)

  if #state.logMessageQueue > 0 then
    for i, msg in pairs(state.logMessageQueue) do
      gui.print(msg)
    end
    state.logMessageQueue = {}
  end

  bufferWidth  = inRect.width - 20
  bufferHeight = inRect.height - 50

  local e = Event.current

  if e.type == EventType.KeyDown then
    if (e.keyCode == KeyCode.Return) then
      gui.OnReturn()
    elseif (e.keyCode == KeyCode.UpArrow) then
      gui.OnUpArrow()
    elseif (e.keyCode == KeyCode.DownArrow) then
      gui.OnDownArrow()
    end
  end

  Text.Font = GameFont.Tiny

  GUI.BeginGroup(inRect)
  if Widgets.ButtonText( Rect.__new(inRect.width - 100, 0, 100, 25), "Reload GUI") then
    gui:reload()
  end

  local status, err = pcall( function()
      state.inputBuffer = Widgets.TextField( Rect.__new(0, inRect.height - 25, inRect.width, 25),
                                             state.inputBuffer)

      state.outputScrollPosition = GUI.BeginScrollView( Rect.__new(0,20,inRect.width,bufferHeight),
                                                        state.outputScrollPosition,
                                                        Rect.__new(0,0,bufferWidth,state.outputHeight) )
      gui.renderOutput()
      GUI.EndScrollView()
  end)

  if not status then
    if typeof(require("MoonSharp.Interpreter.InterpreterException")).IsInstanceOfType(err) then
      Log.Message("Error drawing GUI " .. err.DecoratedMessage)
    else
      Log.Message("Error drawing GUI " .. tostring(err))
    end
  end
  GUI.EndGroup()
end

function MainTabWindow_LuaREPL:get_InitialSize()
  return Vector2.__new(UI.screenWidth / 4 * 3, UI.screenHeight / 2)
end

class( "LuaTest.MainTabWindow_LuaREPL", typeof(require('RimWorld.MainTabWindow')), MainTabWindow_LuaREPL )

function gui.OnReturn()
  gui.appendOutput( ">" .. state.inputBuffer )
  local fn, err = load(state.inputBuffer, "(repl)")
  if not fn then
    gui.appendOutput( "ERROR: " .. tostring(err), defaultErrorStyle )
  else
    local status, result = pcall(fn)
    if status then
      gui.appendOutput( result )
    else
      if typeof(require("MoonSharp.Interpreter.InterpreterException")).IsInstanceOfType(result) then
        gui.appendOutput( "ERROR: " .. result.DecoratedMessage, defaultErrorStyle )
      else
        gui.appendOutput( "ERROR: " .. tostring(result), defaultErrorStyle )
      end
    end
  end
  state.inputHistory[#state.inputHistory + 1] = state.inputBuffer;
  state.historyIndex = -1
  state.inputBuffer = ""
end

function gui.OnUpArrow()
  if state.historyIndex == -1 then
    state.stashedInput = state.inputBuffer
  end

  if state.historyIndex < #state.inputHistory then
    state.historyIndex = state.historyIndex + 1
    state.inputBuffer = state.inputHistory[ #state.inputHistory - state.historyIndex ]
  end
end

function gui.OnDownArrow()
  if state.historyIndex > -1 then
    state.historyIndex = state.historyIndex - 1

    if state.historyIndex == -1 then
      state.inputBuffer = state.stashedInput
    else
      state.inputBuffer = state.inputHistory[ #state.inputHistory - state.historyIndex ]
    end
  end
end

function gui:reload(resetState)
  package.loaded.gui = nil
  for k,v in pairs(require 'gui') do
    self[k] = v
  end
  if not resetState then
    self.inheritState(state)
  end
end

function gui.inheritState(oldstate)
  for k,v in pairs(oldstate) do
    state[k] = v
  end
end

function gui.print(msg)
  gui.appendOutput( msg )
end

function gui.isRectVisible(rect)
  local rectTop = rect.y
  local rectBottom = rectTop + rect.height
  local viewTop = state.outputScrollPosition.y
  local viewBottom = viewTop + bufferHeight

  return (rectTop >= viewTop and rectTop <= viewBottom) or
    (rectBottom >= viewTop and rectBottom <= viewBottom)

end

function gui.renderOutput()
  local y = 0
  for _,x in ipairs(state.output) do
    x.rect.y = y
    if gui.isRectVisible(x.rect) then
      x.render( x.rect, x.content or x, x.style )
      if x.onClick and Widgets.ButtonInvisible( x.rect ) then
        x.onClick()
      end
    end
    y = y + x.rect.height
  end
  state.outputHeight = y
end


function gui.appendOutput(x,style)
  local result = { content=GUIContent.__new() }
  if type(x) == 'string' then
    result.content.text = x
  elseif type(x) == 'userdata' then
    if typeof(require('Verse.ThingDef')).IsInstanceOfType(x) then
      result.content.image = x.uiIcon;
      result.content.text  = x.label;
      result.rect          = Rect.__new(0, state.outputHeight, bufferWidth, 20)
      result.onClick = function()
        Find.WindowStack.Add( require("Verse.Dialog_InfoCard").__new(x) )
      end
    elseif typeof(require('Verse.Thing')).IsInstanceOfType(x) then
      result.content.image = x.def.uiIcon;
      result.content.text  = x.label;
      result.rect          = Rect.__new(0, state.outputHeight, bufferWidth, 20)
      result.onClick = function()
        Find.WindowStack.Add( require("Verse.Dialog_InfoCard").__new(x) )
      end
    else
      result.content.text = tostring(x)
      -- assume it's a static userdata if the tostring starts with "userdata:"
      -- may need to implement an `isstatic` function or something in C#
      if(string.startsWith(result.content.text, "userdata:")) then
        result.content.text = tostring(typeof(x)) .. " (static)"
      end
    end
  else
    result.content.text = tostring(x)
  end

  gui.appendOutputObject(result, style)
end

function gui.appendOutputObject(x, style)
  x.style  = x.style  or style or defaultTextStyle
  x.rect   = x.rect   or Rect.__new(0, 0, bufferWidth, x.style.CalcHeight(x.content, bufferWidth))

  -- x.render = x.render or GUI.Label breaks reloading of class render methods
  if not x.render then
    x.render = GUI.Label
  end

  x.rect.y = state.outputHeight

  if state.outputScrollPosition.y + bufferHeight >= state.outputHeight then
    state.outputScrollPosition.y = state.outputScrollPosition.y + x.rect.height
  end

  state.outputHeight = state.outputHeight + x.rect.height

  state.outputLength = state.outputLength + 1
  state.output[state.outputLength] = x
end

return gui
