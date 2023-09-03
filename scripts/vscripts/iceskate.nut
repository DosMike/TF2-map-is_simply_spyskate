// MIT - DosMike (aka reBane)
// IceSkate TF2 gamemode VScript
// Version 2023-09-03.03
// This script only implements the basics of the game mode: Movement
// It is recommended to make usage of powerups
// Class and weapons limits are up to the mapper

// How to:
// * Create a logic_script named nut_skate
//   * Add this script to it
//   * Set the think function to SkateUpdatePlayer
// * Create a multi-brush trigger volume spanning the skate-able area, of ~32 units height.
//   * Add the output OnStartTouch nut_skate CallScriptFunction AddPlayer
//   * Add the output OnEndTouch nut_skate CallScriptFunction RemovePlayer
// * You can create boost triggers with the output
//   * output nut_skate RunScriptCode `BoostPlayerImpulse(amount, limit)`
//   * output nut_skate RunScriptCode `BoostPlayerStart(amountPerSecond/66.66, limit)`
//   * output nut_skate RunScriptCode `BoostPlayerEnd()`
// convar recommendations:
// tf_grapplinghook_enable 1
// tf_grapplinghook_use_acceleration 1
// tf_powerup_mode 1

ClearGameEventCallbacks();

//  ----- utilities -----

::PlayerManager <- Entities.FindByClassname(null, "tf_player_manager");
::GetPlayerUserID <- function(player)
{
    return NetProps.GetPropIntArray(PlayerManager, "m_iUserID", player.entindex());
}

// ----- gamemode -----

if (Convars.GetInt("sv_airaccelerate") < 20) Convars.SetValue("sv_airaccelerate", 150);

local soundLand = "Taunt.SkatingScorcherLand";
local soundStride = "Taunt.SkatingScorcherStride";

PrecacheScriptSound(soundLand);
PrecacheScriptSound(soundStride);

local skaters = {};
local boosted = {};

local running = false;
function SkateUpdatePlayer() {
    // printl("Skaters: "+skaters.len().tostring())
	if (!running) return;
	foreach(uid,_ in skaters) {
		local client = GetPlayerFromUserID(uid);
		if (client.GetMoveType() != 2) continue; // MOVETYPE_WALK, ignore people noclipping
		local origin = client.GetOrigin();
		local scan = {
			start = origin
			end = Vector(origin.x, origin.y, origin.z - 48.0)
			hullmin = client.GetPlayerMins()
			hullmax = client.GetPlayerMaxs()
			//MASK_PLAYERSOLID			(CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_PLAYERCLIP|CONTENTS_WINDOW|CONTENTS_MONSTER|CONTENTS_GRATE)
			mask = 81931
			ignore = client
		};
		// pos, fraction, hit, enthit, allsolid, startpos, endpos, startsolid, plane_normal, plane_dist, surface_name, surface_flags, surface_props 
		if (!TraceHull(scan) || !("enthit" in scan)) continue;
		// new location
		local position = Vector(scan.pos.x, scan.pos.y, scan.pos.z + 10.0);
		// new velocity, based on surface normal as up, right as right, forward should be the cross
		local absVelocity = client.GetAbsVelocity();
		local up = Vector(0.0, 0.0, 1.0);
		local right = absVelocity.Cross(up);
		local velocity = scan.plane_normal.Cross(right);
		velocity.Norm() // norms in place, returns length -.-
		if (absVelocity.z < -250.0) { //goes down fast, since we ARE snapping to ground, we are landing. apply a speed penalty and dont convert downward velocity forward
			client.EmitSound(soundLand);
			velocity = velocity.Scale(absVelocity.Length2D()*0.9);
		} else {
			velocity = velocity.Scale(absVelocity.Length());
		}
		local angles = client.GetAbsAngles();
		//check if we need to adjust, because teleport causes re-trigger!
		local isValueOff = fabs(origin.z - position.z) > 2.0 || fabs(absVelocity.z - velocity.z) > 1.0;
		if (isValueOff) client.Teleport(true, position, false, angles, true, velocity);
		if (client.GetFlags() & 1) { //FL_ONGROUND
			NetProps.SetPropEntity(self,"m_hGroundEntity",null);
			self.RemoveFlag(1); //FL_ONGROUND
		}
	}
	
	foreach(uid,data in boosted) {
		DoBoostPlayer(GetPlayerFromUserID(uid),data);
	}
	
	//by delaying removal to here, the client needs to be outside for a full think before being removed
	// this is needed because the teleport above re-triggers
	foreach(uid in skaters.keys()) {
		local client = GetPlayerFromUserID(uid);
		if (skaters[uid] == 0) {
			delete skaters[uid];
			client.SetGravity(1.0);
			NetProps.SetPropFloat(client, "m_flGravity", 1.0);
		}
	}
	
	return -1; //should round up to every tick?
}
function AddPlayer() {
	// printl("AddPlayer")
	if (!activator || !activator.IsPlayer() || activator.GetTeam() <= 1) return;
	local uid = GetPlayerUserID(activator);
	if (uid in skaters) {
		skaters[uid] = skaters[uid] + 1;
	} else {
		skaters[uid] <- 1;
		activator.SetGravity(0.000000001);
		NetProps.SetPropFloat(activator, "m_flGravity", 0.000000001);
	}
}
function RemovePlayer() {
	// printl("RemovePlayer")
	if (!activator || !activator.IsPlayer() || activator.GetTeam() <= 1) return;
	local uid = GetPlayerUserID(activator);
	if (uid in skaters) skaters[uid] = skaters[uid] - 1;
}

function BoostPlayerImpulse(amount, max) {
	// printl("BoostPlayerImpulse")
	if (!activator || !activator.IsPlayer() || activator.GetTeam() <= 1) return;
	DoBoostPlayer(activator,{ amount = amount, limit = max });
	activator.EmitSound(soundStride);
}

function BoostPlayerStart(amount, max) {
	// printl("BoostPlayerStart")
	if (activator == null || !activator.IsPlayer() || activator.GetTeam() <= 1) return;
	local uid = GetPlayerUserID(activator);
	if (!(uid in boosted)) {
		boosted[uid] <- { amount = amount, limit = max };
		activator.EmitSound(soundStride);
	}
}
function BoostPlayerEnd() {
	// printl("BoostPlayerEnd")
	if (activator == null || !activator.IsPlayer() || activator.GetTeam() <= 1) return;
	local uid = GetPlayerUserID(activator);
	if (uid in boosted) delete boosted[uid];
}

function IsSkating(player) {
	return GetPlayerUserID(player) in skaters;
}

function DoBoostPlayer(player, params) {
	if (IsSkating(player)) {
		local velocity = player.GetAbsVelocity();
		if (velocity.Length2D() < params.limit) {
			local speed = velocity.Norm();
			player.SetAbsVelocity(velocity.Scale(speed+params.amount));
		}
	}
}

function OnGameEvent_teamplay_round_active(params) {
	running = true;
}

function OnGameEvent_player_spawn(params) {
	//restore properties if e.g. waiting for player ends
	if (params.userid in skaters) {
		delete skaters[params.userid];
	}
	local client = GetPlayerFromUserID(params.userid);
	client.SetGravity(1.0);
	NetProps.SetPropFloat(client, "m_flGravity", 1.0);
	client.SetCollisionGroup(2); // COLLISION_GROUP_DEBRIS_TRIGGER, also makes grappling hook phase through players
}

function OnScriptHook_OnTakeDamage(params) {
	//no fall damage if skating
	if(params.const_entity.IsPlayer() && IsSkating(params.const_entity) && params.inflictor && params.inflictor.GetEntityIndex() == 0) {
		params.damage = 0;
	}
}

// ----- register events -----
__CollectGameEventCallbacks(this);
