local UI              = require('Verse.UI')
local GUI             = require('UnityEngine.GUI')
local GUIStyle        = require('UnityEngine.GUIStyle')
local GUIContent      = require('UnityEngine.GUIContent')
local GUIUtility      = require('UnityEngine.GUIUtility')
local Event           = require('UnityEngine.Event')
local EventType       = require('UnityEngine.EventType')
local KeyCode         = require('UnityEngine.KeyCode')
local Widgets         = require('Verse.Widgets')
local Log             = require('Verse.Log')
local Text            = require('Verse.Text')
local TextAnchor      = require('UnityEngine.TextAnchor')
local Color           = require('UnityEngine.Color')
local GameFont        = require('Verse.GameFont')
local Find            = require('Verse.Find')
local Vector2         = require('UnityEngine.Vector2')
local Rect            = require('UnityEngine.Rect')
local HarmonyInstance = require('Harmony.HarmonyInstance')
local HarmonyMethod   = require('Harmony.HarmonyMethod')
local TextEditor      = require('UnityEngine.TextEditor')
local Find            = require('Verse.Find')

local _

local CONTROL_NAME_REPL_INPUT = 'replInput'

local Window_LuaREPL        = {}
local MainTabWindow_LuaREPL = {popText = 'Pop Out'}
local EditWindow_LuaREPL    = {popText = 'Pop In'}
setmetatable(MainTabWindow_LuaREPL, {__index=Window_LuaREPL})
setmetatable(EditWindow_LuaREPL, {__index=Window_LuaREPL})

local defaultTextStyle = GUIStyle.__new(Text.fontStyles[0])
defaultTextStyle.alignment = TextAnchor.MiddleLeft

local defaultErrorStyle = GUIStyle.__new(defaultTextStyle)
defaultErrorStyle.normal.textColor = Color.red

function Window_LuaREPL:__new()
  self.output               = {}
  self.outputLength         = 0
  self.outputHeight         = 0
  self.inputBuffer          = ""
  self.outputScrollPosition = Vector2.__new()
  self.inputHistory         = {}
  self.stashedInput         = ""
  self.historyIndex         = -1
  self.logMessageQueue      = {}
end

function Window_LuaREPL:CheckForNewLogMessages()
  if #self.logMessageQueue > 0 then
    for _, msg in ipairs(self.logMessageQueue) do
      self:AppendOutput(msg)
    end
    self.logMessageQueue = {}
  end
end

function Window_LuaREPL:HandleEvent(event)
  if event.type == EventType.KeyDown and
    GUI.GetNameOfFocusedControl() == CONTROL_NAME_REPL_INPUT
  then
    if (event.keyCode == KeyCode.Return) then
      self:HandleInputLine()
    elseif (event.keyCode == KeyCode.UpArrow) then
      self:ScrollHistory(1)
    elseif (event.keyCode == KeyCode.DownArrow) then
      self:ScrollHistory(-1)
    elseif (event.keyCode == KeyCode.A and event.control and event.shift) then
      self:SetInputCursorPosition(0, #self.inputBuffer)
    elseif (event.keyCode == KeyCode.A and event.control) then
      self:SetInputCursorPosition(0)
    elseif (event.keyCode == KeyCode.E and event.control) then
      self:SetInputCursorPosition(#self.inputBuffer)
    else
      return
    end
    event.Use()
  end
end

function Window_LuaREPL:SetInputCursorPosition(cursorIndex, selectIndex)
  if selectIndex == nil then
    selectIndex = cursorIndex
  end
  local editor = GUIUtility.GetStateObject( typeof(TextEditor), GUIUtility.keyboardControl )
  -- HACK: update text so we can move position in ScrollHistory
  editor.text = self.inputBuffer
  editor.cursorIndex = cursorIndex
  editor.selectIndex = selectIndex
end

function Window_LuaREPL:RenderControls(inRect)
  self.bufferWidth  = inRect.width - 20
  self.bufferHeight = inRect.height - 50

  GUI.BeginGroup(inRect)

  Text.Font = GameFont.Tiny

  if Widgets.ButtonText( Rect.__new(inRect.width - 150, 0, 100, 25), "Reload GUI") then
    self:Reload()
  end

  if Widgets.ButtonText( Rect.__new(inRect.width - 250, 0, 100, 25), self.popText) then
    self:PopInOrOut()
  end

  GUI.SetNextControlName( CONTROL_NAME_REPL_INPUT )
  self.inputBuffer = Widgets.TextField(
    Rect.__new(0, inRect.height - 25, inRect.width - 15, 25),
    self.inputBuffer)

  self.outputScrollPosition = GUI.BeginScrollView(
    Rect.__new(0,20,inRect.width,self.bufferHeight),
    self.outputScrollPosition,
    Rect.__new(0,0,self.bufferWidth,self.outputHeight) )
  self:RenderOutput()
  GUI.EndScrollView()

  GUI.EndGroup()
end

function Window_LuaREPL:DoWindowContents(inRect)
  self:CheckForNewLogMessages()
  self:HandleEvent(Event.current)
  self:RenderControls(inRect)
end

function Window_LuaREPL:get_InitialSize()
  return Vector2.__new(UI.screenWidth / 4 * 3, UI.screenHeight / 2)
end

function Window_LuaREPL:HandleInputLine()
  self:AppendOutput( ">" .. self.inputBuffer )
  local fn, err = load(self.inputBuffer, "(repl)")
  if not fn then
    self:AppendOutput( "ERROR: " .. tostring(err), defaultErrorStyle )
  else
    local status, result = pcall(fn)
    if status then
      self:AppendOutput( result )
    else
      if typeof(require("MoonSharp.Interpreter.InterpreterException")).IsInstanceOfType(result) then
        self:AppendOutput( "ERROR: " .. result.DecoratedMessage, defaultErrorStyle )
      else
        self:AppendOutput( "ERROR: " .. tostring(result), defaultErrorStyle )
      end
    end
  end
  self.inputHistory[#self.inputHistory + 1] = self.inputBuffer;
  self.historyIndex = -1
  self.inputBuffer = ''
end

function Window_LuaREPL:ScrollHistory(offset)
  if self.historyIndex == -1 then
    self.stashedInput = self.inputBuffer
  end

  local newIndex = self.historyIndex + offset
  newIndex = math.min(newIndex, #self.inputHistory)
  newIndex = math.max(newIndex, -1)

  if newIndex ~= self.historyIndex then
    if newIndex >= 0 then
      self.inputBuffer = self.inputHistory[ #self.inputHistory - newIndex ]
    else
      self.inputBuffer = self.stashedInput
    end
    self.historyIndex = newIndex
    self:SetInputCursorPosition(#self.inputBuffer)
  end
end

function Window_LuaREPL:Reload(resetState)
  package.loaded.gui = nil
  Window_LuaREPL =require('gui')
end

function Window_LuaREPL:IsRectVisible(rect)
  local rectTop = rect.y
  local rectBottom = rectTop + rect.height
  local viewTop = self.outputScrollPosition.y
  local viewBottom = viewTop + self.bufferHeight

  return (rectTop >= viewTop and rectTop <= viewBottom) or
    (rectBottom >= viewTop and rectBottom <= viewBottom)
end

function Window_LuaREPL:RenderOutput()
  local y = 0
  for _,x in ipairs(self.output) do
    x.rect.y = y
    if self:IsRectVisible(x.rect) then
      x.render( x.rect, x.content or x, x.style )
      if x.onClick and Widgets.ButtonInvisible( x.rect ) then
        x.onClick()
      end
    end
    y = y + x.rect.height
  end
  self.outputHeight = y
end

function Window_LuaREPL:AppendOutput(x,style)
  local result = { content=GUIContent.__new() }
  if type(x) == 'string' then
    result.content.text = x
  elseif type(x) == 'userdata' then
    if typeof(require('Verse.ThingDef')).IsInstanceOfType(x) then
      result.content.image = x.uiIcon;
      result.content.text  = x.label;
      result.rect          = Rect.__new(0, self.outputHeight, self.bufferWidth, 20)
      result.onClick = function()
        Find.WindowStack.Add( require("Verse.Dialog_InfoCard").__new(x) )
      end
    elseif typeof(require('Verse.Thing')).IsInstanceOfType(x) then
      result.content.image = x.def.uiIcon;
      result.content.text  = x.label;
      result.rect          = Rect.__new(0, self.outputHeight, self.bufferWidth, 20)
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

  self:AppendOutputObject(result, style)
end

function Window_LuaREPL:AppendOutputObject(x, style)
  x.style  = x.style  or style or defaultTextStyle
  x.rect   = x.rect   or Rect.__new(0, 0, self.bufferWidth, x.style.CalcHeight(x.content, self.bufferWidth))

  -- x.render = x.render or GUI.Label breaks reloading of class render methods
  if not x.render then
    x.render = GUI.Label
  end

  x.rect.y = self.outputHeight

  if self.outputScrollPosition.y + self.bufferHeight >= self.outputHeight then
    self.outputScrollPosition.y = self.outputScrollPosition.y + x.rect.height
  end

  self.outputHeight = self.outputHeight + x.rect.height

  self.outputLength = self.outputLength + 1
  self.output[self.outputLength] = x
end

local type_MainTabWindow_LuaREPL = class(
    "LuaTest.MainTabWindow_LuaREPL",
    typeof(require('RimWorld.MainTabWindow')),
    MainTabWindow_LuaREPL )

local type_EditWindow_LuaREPL = class(
    "LuaTest.EditWindow_LuaREPL",
    typeof(require('Verse.EditWindow')),
    EditWindow_LuaREPL )

function MainTabWindow_LuaREPL:PopInOrOut()
  Find.WindowStack.Add(require('LuaTest.EditWindow_LuaREPL').__new())
  self:Close(true)
end

function EditWindow_LuaREPL:PopInOrOut()
  local def = require ('Verse.DefDatabase`1[RimWorld.MainButtonDef]').GetNamed("LuaREPL")
  Find.MainTabsRoot.SetCurrentTab(def)
  self:Close(true)
end


-- Harmony Patches
--[[
if not pcall(|| require('LuaREPL.LogMessageQueuePatch')) then
  local harmony = HarmonyInstance.Create("luarepl")

  -- Intercept debug log messages
  local patchClass = class(
    'LuaREPL.LogMessageQueuePatch',
    typeof(require('System.Object')),
    {postfix=function(msg)
       Window_LuaREPL.logMessageQueue[#Window_LuaREPL.logMessageQueue+1] = msg.text
    end},
    function(typeBuilder)
      local method = typeBuilder.AddStaticMethod(
        'postfix',
        typeof(require('System.Void')),
        { typeof(require('Verse.LogMessage')) },
        'postfix'
      )
      method.DefineParameter(1,0,"msg")
    end
  )

  local original = typeof(require('Verse.LogMessageQueue')).GetMethod("Enqueue")
  local postfix  = patchClass.GetMethod("postfix")

  harmony.Patch(original, nil, HarmonyMethod.__new(postfix))
  end
]]--


return Window_LuaREPL
