-- Drags that follow the cursor every frame, for placement and groups. ONHOLD
-- only fires while the cursor is over the held component, so a fast drag
-- moved by it falls behind and drops; Mouse.GetPosition doesn't.

local gameClock = require("GameData/Trackers/game-clock")

local dragFollow = {}

local EVENT_ID = "runeAurasDragFollow"
-- Logic ticks without an ONHOLD after which the button counts as released.
local HOLD_TIMEOUT_TICKS = 5
-- Window pixels per interface unit outside which a measurement is wrong.
local MIN_SCALE, MAX_SCALE = 0.25, 4

---@class DragState
---@field root userdata The component that moves.
---@field clicked userdata The component holding the hooks: root, or a group's handle.
---@field start { x: number, y: number } root's position when the drag started.
---@field mouse userdata Mouse position in window pixels when the drag started.
---@field scale number Window pixels per interface unit.
---@field lastHold integer? Logic tick of the last ONHOLD.
---@field heldAt { x: number, y: number } root's position at the last ONHOLD.
---@field onMove fun(left: number, top: number)
---@field onEnd fun()

---@type DragState?
local active = nil

--- Window pixels per interface unit, from where the grab point is in each.
--- Mouse.GetPosition has no UI scaling applied, while positions do.
---@param clicked userdata
---@param grabX number ONCLICK's x, relative to `clicked`.
---@param mouse userdata The mouse position at the click.
---@return number scale 1 if it can't be measured.
local function measureScale(clicked, grabX, mouse)
    local unitsX = clicked.xyGlobal.x + grabX
    if unitsX <= 0 then return 1 end
    local scale = mouse.x / unitsX
    if scale < MIN_SCALE or scale > MAX_SCALE then return 1 end
    return scale
end

--- Stops following the cursor, without telling the caller.
local function stopFollowing()
    active = nil
    Event.Draw.Unsubscribe(EVENT_ID)
end

--- Each frame: moves the display to the cursor, or ends the drag once ONHOLD
--- has stopped. The API has no button state, so that's how a release the
--- display didn't see (the cursor was off it) is found.
local function follow()
    local drag = active
    local tick = gameClock.LogicTick()
    local released = tick ~= nil and drag.lastHold ~= nil and tick - drag.lastHold > HOLD_TIMEOUT_TICKS
    if released then
        stopFollowing()
        -- It followed the cursor on past the release; put it back.
        drag.onMove(drag.heldAt.x, drag.heldAt.y)
        drag.onEnd()
        return
    end
    local mouse = Mouse.GetPosition()
    if mouse == nil then return end
    drag.onMove(drag.start.x + (mouse.x - drag.mouse.x) / drag.scale,
        drag.start.y + (mouse.y - drag.mouse.y) / drag.scale)
end

--- Starts moving a display with the cursor every frame, until released.
---@param root userdata The component that moves.
---@param clicked userdata The component that was clicked, holding the hooks.
---@param grabX number ONCLICK's x, relative to `clicked`.
---@param onMove fun(left: number, top: number) Moves root, in unrounded interface units.
---@param onEnd fun() The caller's end of drag, called on a release it didn't see.
---@return boolean started false without a mouse (mobile): the caller moves it from ONHOLD instead.
function dragFollow.Start(root, clicked, grabX, onMove, onEnd)
    local mouse = Mouse.GetPosition()
    if mouse == nil then return false end
    -- A drag still waiting out its timeout ends first.
    if active ~= nil then active.onEnd() end
    active = {
        root = root, clicked = clicked, onMove = onMove, onEnd = onEnd,
        start = { x = root.x, y = root.y }, heldAt = { x = root.x, y = root.y },
        mouse = mouse, scale = measureScale(clicked, grabX, mouse), lastHold = gameClock.LogicTick(),
    }
    Event.Draw.Subscribe(EVENT_ID, follow)
    return true
end

--- Whether a component's drag follows the cursor.
---@param clicked userdata
---@return boolean
function dragFollow.IsFollowing(clicked)
    return active ~= nil and active.clicked == clicked
end

--- Notes the button is still held. Call from the dragged component's ONHOLD.
function dragFollow.Hold()
    active.lastHold = gameClock.LogicTick()
    active.heldAt = { x = active.root.x, y = active.root.y }
end

--- Stops following a component's drag, if it is. Call when the caller ends it.
---@param clicked userdata
function dragFollow.Cancel(clicked)
    if dragFollow.IsFollowing(clicked) then stopFollowing() end
end

--- Wraps a drag's release handler for ONRELEASE and ONDRAGCOMPLETE. A thin
--- display can slip from under a fast cursor for a frame, and the game
--- reports that as a release; one with the cursor off the display is left
--- to the ONHOLD timeout, which tells a slip from a real release.
---@param clicked userdata The component the hooks are on.
---@param stopDrag fun(): boolean? The caller's end of drag.
---@return fun(): boolean? handler
function dragFollow.ReleaseHandler(clicked, stopDrag)
    return function()
        local slipped = dragFollow.IsFollowing(clicked) and not clicked.isMouseOver
        if slipped then return false end
        return stopDrag()
    end
end

return dragFollow
