--- A bucket to catch events in. **Gemini:Bucket-1.0** provides throttling of events that fire in bursts and
-- your addon only needs to know about the full burst.
-- 
-- This Bucket implementation works as follows:\\
--   Initially, no schedule is running, and its waiting for the first event to happen.\\
--   The first event will start the bucket, and get the scheduler running, which will collect all
--   events in the given interval. When that interval is reached, the bucket is pushed to the 
--   callback and a new schedule is started. When a bucket is empty after its interval, the scheduler is 
--   stopped, and the bucket is only listening for the next event to happen, basically back in its initial state.
-- 
-- In addition, the buckets collect information about the "arg1" argument of the events that fire, and pass those as a 
-- table to your callback. This functionality was mostly designed for the UNIT_* events.\\
-- The table will have the different values of "arg1" as keys, and the number of occurances as their value, e.g.\\
--   { ["player"] = 2, ["target"] = 1, ["party1"] = 1 }
--
-- **Gemini:Bucket-1.0** can be embeded into your addon, either explicitly by calling GeminiBucket:Embed(MyAddon) or by 
-- specifying it as an embeded library in your AceAddon. All functions will be available on your addon object
-- and can be accessed directly, without having to explicitly call GeminiBucket itself.\\
-- It is recommended to embed GeminiBucket, otherwise you'll have to specify a custom `self` on all calls you
-- make into GeminiBucket.
-- @usage
-- MyAddon = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("BucketExample", false, {}, "Gemini:Bucket-1.0")
-- 
-- function MyAddon:OnEnable()
--   -- Register a bucket that listens to all the HP related events, 
--   -- and fires once per second
--   self:RegisterBucketEvent({"CombatLogDamage", "CombatLogHeal"}, 1, "OnHealHarm")
-- end
--
-- function MyAddon:OnHealHarm(messages)
--   local nHealed, nHarmed = 0,0
--   for k,v in pairs(messages)
--     if k.unitTarget == GameLib.GetPlayerUnit() then
--       if k.eDamageType then
--         nHarmed = nHarmed + v
--       else
--         nHealed = nHealed + v
--     end
--   end
--   if nHealed > 0 then
--     Print("You were healed " .. nHealed .. " times!")
--   end
--   if nHarmed > 0 then
--     Print("You were harmed " .. nHarmed .. " times!")
--   end
-- end
-- @class file
-- @name Gemini:Bucket-1.0.lua

local MAJOR, MINOR = "Gemini:Bucket-1.0", 2
-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end
-- Set a reference to the actual package or create an empty table
local GeminiBucket = APkg and APkg.tPackage or {}

GeminiBucket.buckets = GeminiBucket.buckets or {}
GeminiBucket.embeds = GeminiBucket.embeds or {}


-- Library references, bound in OnLoad
local GeminiTimer
local GeminiEvent

-- Lua APIs
local tconcat = table.concat
local type, next, pairs, select = type, next, pairs, select
local tonumber, tostring, rawset = tonumber, tostring, rawset
local assert, loadstring, error = assert, loadstring, error

-- Global vars/functions that we don't upvalue since they might get hooked, or upgraded
-- List them here for Mikk's FindGlobals script
-- GLOBALS: 

local bucketCache = setmetatable({}, {__mode='k'})

--[[
	 xpcall safecall implementation
]]

local tLibError = Apollo.GetPackage("Gemini:LibError-1.0")
local fnErrorHandler = tLibError and tLibError.tPackage.Error or Print

local xpcall = xpcall

local function CreateDispatcher(argCount)
	local code = [[
		local xpcall, eh = ...
		local method, ARGS
		local function call() return method(ARGS) end
	
		local function dispatch(func, ...)
			 method = func
			 if not method then return end
			 ARGS = ...
			 return xpcall(call, eh)
		end
	
		return dispatch
	]]
	
	local ARGS = {}
	for i = 1, argCount do ARGS[i] = "arg"..i end
	code = code:gsub("ARGS", tconcat(ARGS, ", "))
	return assert(loadstring(code, "safecall Dispatcher["..argCount.."]"))(xpcall, fnErrorHandler)
end

local Dispatchers = setmetatable({}, {__index=function(self, argCount)
	local dispatcher = CreateDispatcher(argCount)
	rawset(self, argCount, dispatcher)
	return dispatcher
end})
Dispatchers[0] = function(func)
	return xpcall(func, fnErrorHandler)
end
 
local function safecall(func, ...)
	return Dispatchers[select('#', ...)](func, ...)
end

-- FireBucket ( bucket )
--
-- send the bucket to the callback function and schedule the next FireBucket in interval seconds
local function FireBucket(bucket)
	local received = bucket.received
	
	-- we dont want to fire empty buckets
	if next(received) then
		local callback = bucket.callback
		if type(callback) == "string" then
			safecall(bucket.object[callback], bucket.object, received)
		else
			safecall(callback, received)
		end
		
		for k in pairs(received) do
			received[k] = nil
		end
		
		-- if the bucket was not empty, schedule another FireBucket in interval seconds
		bucket.timer = GeminiTimer.ScheduleTimer(bucket, FireBucket, bucket.interval, bucket)
	else -- if it was empty, clear the timer and wait for the next event
		bucket.timer = nil
	end
end

-- BucketHandler ( event, arg1 )
-- 
-- callback func for GeminiEvent
-- stores arg1 in the received table, and schedules the bucket if necessary
local function BucketHandler(self, event, arg1)
	if arg1 == nil then
		arg1 = "nil"
	end
	
	self.received[arg1] = (self.received[arg1] or 0) + 1
	
	-- if we are not scheduled yet, start a timer on the interval for our bucket to be cleared
	if not self.timer then
		self.timer = GeminiTimer.ScheduleTimer(self, FireBucket, self.interval, self)
	end
end

-- RegisterBucket( event, interval, callback, isMessage )
--
-- event(string or table) - the event, or a table with the events, that this bucket listens to
-- interval(int) - time between bucket fireings
-- callback(func or string) - function pointer, or method name of the object, that gets called when the bucket is cleared
-- isMessage(boolean) - register GeminiEvent Messages instead of game events
local function RegisterBucket(self, event, interval, callback, isMessage)
	if type(event) ~= "string" and type(event) ~= "table" then error("Usage: RegisterBucket(event, interval, callback): 'event' - string or table expected.", 3) end
	if not callback then
		if type(event) == "string" then
			callback = event
		else
			error("Usage: RegisterBucket(event, interval, callback): cannot omit callback when event is not a string.", 3)
		end
	end
	if not tonumber(interval) then error("Usage: RegisterBucket(event, interval, callback): 'interval' - number expected.", 3) end
	if type(callback) ~= "string" and type(callback) ~= "function" then error("Usage: RegisterBucket(event, interval, callback): 'callback' - string or function or nil expected.", 3) end
	if type(callback) == "string" and type(self[callback]) ~= "function" then error("Usage: RegisterBucket(event, interval, callback): 'callback' - method not found on target object.", 3) end
	
	local bucket = next(bucketCache)
	if bucket then
		bucketCache[bucket] = nil
	else
		bucket = { handler = BucketHandler, received = {} }
	end
	bucket.object, bucket.callback, bucket.interval = self, callback, tonumber(interval)
	
	local regFunc = isMessage and GeminiEvent.RegisterMessage or GeminiEvent.RegisterEvent
	
	if type(event) == "table" then
		for _,e in pairs(event) do
			regFunc(bucket, e, "handler")
		end
	else
		regFunc(bucket, event, "handler")
	end
	
	local handle = tostring(bucket)
	GeminiBucket.buckets[handle] = bucket
	
	return handle
end

--- Register a Bucket for an event (or a set of events)
-- @param event The event to listen for, or a table of events.
-- @param interval The Bucket interval (burst interval)
-- @param callback The callback function, either as a function reference, or a string pointing to a method of the addon object.
-- @return The handle of the bucket (for unregistering)
-- @usage
-- MyAddon = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("MyAddon", false, {}, "Gemini:Bucket-1.0")
-- MyAddon:RegisterBucketEvent("UnitCreated", 0.2,"OnUnitsCreated")
-- 
-- function MyAddon:OnUnitsCreated()
--   -- do stuff
-- end

function GeminiBucket:RegisterBucketEvent(event, interval, callback)
	return RegisterBucket(self, event, interval, callback, false)
end

--- Register a Bucket for an GeminiEvent-3.0 addon message (or a set of messages)
-- @param message The message to listen for, or a table of messages.
-- @param interval The Bucket interval (burst interval)
-- @param callback The callback function, either as a function reference, or a string pointing to a method of the addon object.
-- @return The handle of the bucket (for unregistering)
-- @usage
-- MyAddon = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("MyAddon", false, {}, "Gemini:Bucket-1.0")
-- MyAddon:RegisterBucketEvent("SomeAddon_InformationMessage", 0.2, "ProcessData")
-- 
-- function MyAddon:ProcessData()
--   -- do stuff
-- end
function GeminiBucket:RegisterBucketMessage(message, interval, callback)
	return RegisterBucket(self, message, interval, callback, true)
end

--- Unregister any events and messages from the bucket and clear any remaining data.
-- @param handle The handle of the bucket as returned by RegisterBucket*
function GeminiBucket:UnregisterBucket(handle)
	local bucket = GeminiBucket.buckets[handle]
	if bucket then
		GeminiEvent.UnregisterAllEvents(bucket)
		GeminiEvent.UnregisterAllMessages(bucket)
		
		-- clear any remaining data in the bucket
		for k in pairs(bucket.received) do
			bucket.received[k] = nil
		end
		
		if bucket.timer then
			GeminiTimer.CancelTimer(bucket, bucket.timer)
			bucket.timer = nil
		end
		
		GeminiBucket.buckets[handle] = nil
		-- store our bucket in the cache
		bucketCache[bucket] = true
	end
end

--- Unregister all buckets of the current addon object (or custom "self").
function GeminiBucket:UnregisterAllBuckets()
	-- hmm can we do this more efficient? (it is not done often so shouldn't matter much)
	for handle, bucket in pairs(GeminiBucket.buckets) do
		if bucket.object == self then
			GeminiBucket.UnregisterBucket(self, handle)
		end
	end
end



-- embedding and embed handling
local mixins = {
	"RegisterBucketEvent",
	"RegisterBucketMessage", 
	"UnregisterBucket",
	"UnregisterAllBuckets",
} 

-- Embeds GeminiBucket into the target object making the functions from the mixins list available on target:..
-- @param target target object to embed GeminiBucket in
function GeminiBucket:Embed( target )
	for _, v in pairs( mixins ) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

function GeminiBucket:OnEmbedDisable( target )
	target:UnregisterAllBuckets()
end

for addon in pairs(GeminiBucket.embeds) do
	GeminiBucket:Embed(addon)
end

-- Initialization routines
function GeminiBucket:OnLoad()
	GeminiTimer = Apollo.GetPackage("Gemini:Timer-1.0").tPackage
	GeminiEvent = Apollo.GetPackage("Gemini:Event-1.0").tPackage
end

function GeminiBucket:OnDependencyError(strDep, strError)
	error(MAJOR .. " couldn't load " .. strDep .. ". Fatal error: " .. strError)
	return false
end

Apollo.RegisterPackage(GeminiBucket, MAJOR, MINOR, {"Gemini:Timer-1.0","Gemini:Event-1.0"})
