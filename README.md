GeminiBucket
============

Wildstar Library - Provides throttling of events that fire in bursts and your addon only needs to know about the full burst.

A bucket to catch events in. 
GeminiBucket-1.0 provides throttling of events that fire in bursts and your addon only needs to know about the full burst.

This Bucket implementation works as follows:
Initially, no schedule is running, and its waiting for the first event to happen.
The first event will start the bucket, and get the scheduler running, which will collect all events in the given interval. When that interval is reached, the bucket is pushed to the callback and a new schedule is started. When a bucket is empty after its interval, the scheduler is stopped, and the bucket is only listening for the next event to happen, basically back in its initial state.

In addition, the buckets collect information about the "arg1" argument of the events that fire, and pass those as a table to your callback.
The table will have the different values of "arg1" as keys, and the number of occurances as their value, e.g.
{ ["player"] = 2, ["target"] = 1, ["party1"] = 1 }
Note: Currently this has some issues as the arg1 tends to be a unit object which can fall out of scope due to this table having weak keys.

**TODO:** Decide if store something else or stop using weak keys

GeminiBucket-1.0 can be embeded into your addon, either explicitly by calling AceBucket:Embed(MyAddon) or by specifying it as an embeded library in your GeminiAddon. All functions will be available on your addon object and can be accessed directly, without having to explicitly call AceBucket itself.
It is recommended to embed AceBucket, otherwise you'll have to specify a custom `self` on all calls you make into AceBucket.

##Example

```lua
MyAddon = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("BucketExample", "Gemini:Bucket-1.0")

function MyAddon:OnEnable()
  -- Register a bucket that listens to all the HP related events, 
  -- and fires once per second
  self:RegisterBucketEvent({"CombatLogDamage", "CombatLogHeal"}, 1, "OnHealHarm")
end

function MyAddon:OnHealHarm(messages)
  local nHealed, nHarmed = 0,0
  for k,v in pairs(messages)
    if k.unitTarget == GameLib.GetPlayerUnit() then
      if k.eDamageType then
        nHarmed = nHarmed + v
      else
        nHealed = nHealed + v
    end
  end
  if nHealed > 0 then
    Print("You were healed " .. nHealed .. " times!")
  end
  if nHarmed > 0 then
    Print("You were harmed " .. nHarmed .. " times!")
  end
end
```


##AceBucket:RegisterBucketEvent(event, interval, callback)
Register a Bucket for an event (or a set of events)

###Parameters

**event**

		The event to listen for, or a table of events.

**interval**

		The Bucket interval (burst interval)

**callback**

		The callback function, either as a function reference, or a string pointing to a method of the addon object.

###Return value

The handle of the bucket (for unregistering)

###Usage

```lua
MyAddon = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("BucketExample", "Gemini:Bucket-1.0")
MyAddon:RegisterBucketEvent("UnitCreated", 0.2,"OnUnitsCreated")

function MyAddon:OnUnitsCreated()
  -- do stuff
end
```


##AceBucket:RegisterBucketMessage(message, interval, callback)
Register a Bucket for an GeminiEvent-1.0 addon message (or a set of messages)

###Parameters

**message**

		The message to listen for, or a table of messages.

**interval**

		The Bucket interval (burst interval)

**callback**

		The callback function, either as a function reference, or a string pointing to a method of the addon object.

###Return value

The handle of the bucket (for unregistering)

###Usage

```lua
MyAddon = Apollo.GetPackage("Gemini:Addon-1.0").tPackage:NewAddon("BucketExample", "Gemini:Bucket-1.0")
MyAddon:RegisterBucketEvent("SomeAddon_InformationMessage", 0.2, "ProcessData")

function MyAddon:ProcessData()
  -- do stuff
end
```

##AceBucket:UnregisterAllBuckets()
Unregister all buckets of the current addon object (or custom "self").



##AceBucket:UnregisterBucket(handle)
Unregister any events and messages from the bucket and clear any remaining data.

###Parameters

**handle**

		The handle of the bucket as returned by RegisterBucket*
