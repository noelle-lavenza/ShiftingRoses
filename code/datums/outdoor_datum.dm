//todo: handle moving sunlight turfs - see various uses of get_turf in lighting_object


/*

Sunlight System

	Objects + Details
		Sunlight Objects (this file)
			- Grayscale version of lighting_object
			- Has 3 states
				- SKY_BLOCKED  (0)
					- Turfs that have an opaque turf above them. Has no light themselves but is affected by SKY_VISIBLE_BORDER
				- SKY_VISIBLE (1)
					- Turfs that with no opaque turfs above it (no roof, glass roof, etc), with no neighbouring SKY_BLOCKED tiles
					  Emits no light, but is fully white to display the overlay color
				- SKY_VISIBLE_BORDER  (2)
					- Turfs that with no opaque turfs above it (no roof, glass roof, etc), which neighbour at least one SKY_BLOCKED tile.
				     Emits light to SKY_BLOCKED tiles, and fully white to display the overlay color

*/

/obj/proc/weather_act_on(weather_trait, severity)
	return

/atom/movable/outdoor_effect
	name = "outdoor effect"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	plane = WEATHER_EFFECT_PLANE

	var/state // If we can see the see the sky, are blocked, or we have a blocked neighbour (SKY_BLOCKED/VISIBLE/VISIBLE_BORDER)
	var/weatherproof // If we have a weather overlay

	var/turf/source_turf
	var/mutable_appearance/sunlight_overlay
	var/list/datum/lighting_corner/affecting_corners

/atom/movable/outdoor_effect/Initialize(mapload)
	. = ..()
	source_turf = loc
	if(source_turf.outdoor_effect)
		qdel(source_turf.outdoor_effect, force = TRUE)
	source_turf.outdoor_effect = src

/atom/movable/outdoor_effect/Destroy(force)
	if(!force)
		return QDEL_HINT_LETMELIVE

	//If we are a source of light - disable it, to fix out corner refs
	disable_sunlight()

	//Remove ourselves from our turf
	if(source_turf && source_turf.outdoor_effect == src)
		source_turf.outdoor_effect = null

	return ..()

/atom/movable/outdoor_effect/proc/disable_sunlight()
	var/list/turf/to_update = list()
	for(var/datum/lighting_corner/C in affecting_corners)
		LAZYREMOVE(C.sunlight_objects, src)
		C.get_sunlight_falloff()
		to_update |= C.masters
	to_update |= source_turf /* get our calculated indoor lighting */
	GLOB.SUNLIGHT_QUEUE_CORNER |= to_update

	//Empty our affecting_corners list
	affecting_corners = null

/atom/movable/outdoor_effect/proc/process_state()
	switch(state)
		if(SKY_BLOCKED)
			disable_sunlight() /* Do our indoor processing */
		if(SKY_VISIBLE_BORDER)
			calc_sunlight_spread()

#define GLOBAL_LIGHT_RANGE 3

#define HARD_SUN 0.5 /* our hyperboloidy modifyer funky times - I wrote this in like, 2020 and can't remember how it works - I think it makes a 3D cone shape with a flat top */
/* calculate the indoor corners we are affecting */
#define SUN_FALLOFF(C, T) (1 - CLAMP01(sqrt((C.x - T.x) ** 2 + (C.y - T.y) ** 2 - HARD_SUN) / max(1, GLOBAL_LIGHT_RANGE)))

/atom/movable/outdoor_effect/proc/calc_sunlight_spread()
	var/list/turf/turfs = list()
	var/turf/T
	var/list/tempMasterList = list() /* to mimimize double ups */
	var/list/corners = list() /* corners we are currently affecting */

	//Set lum so we can see things
	var/oldLum = luminosity
	luminosity = GLOBAL_LIGHT_RANGE

	for(T in view(CEILING(GLOBAL_LIGHT_RANGE, 1), source_turf))
		if(T.opacity) /* get_corners used to do opacity checks for arse */
			continue
		if (!T.lighting_corners_initialised)
			T.lighting_build_overlay()
		corners |= T.corners
		turfs += T

	//restore lum
	luminosity = oldLum

	/* fix up the lists */
	/* add ourselves and our distance to the corner */
	LAZYINITLIST(affecting_corners)
	var/list/L = corners - affecting_corners
	affecting_corners += L
	for(var/datum/lighting_corner/C as anything in L)
		LAZYSET(C.sunlight_objects, src, SUN_FALLOFF(C, source_turf))
		if(C.sunlight_objects[src] > C.sunFalloff) /* if are closer than current dist, update the corner */
			C.sunFalloff = C.sunlight_objects[src]
			tempMasterList |= C.masters

	L = affecting_corners - corners // Now-gone corners, remove us from the affecting.
	affecting_corners -= L
	for(var/datum/lighting_corner/C as anything in L)
		LAZYREMOVE(C.sunlight_objects, src)
		C.get_sunlight_falloff()
		tempMasterList |= C.masters

	GLOB.SUNLIGHT_QUEUE_CORNER += tempMasterList /* update the boys */

#undef GLOBAL_LIGHT_RANGE
#undef HARD_SUN
#undef SUN_FALLOFF

/* Related object changes */
/* I moved this here to consolidate sunlight changes as much as possible, so its easily disabled */

/* area fuckery */
/area/var/turf/pseudo_roof

/* turf fuckery */
/turf/var/tmp/atom/movable/outdoor_effect/outdoor_effect /* a turf's sunlight overlay */
/turf/var/turf/pseudo_roof /* our roof turf - may be a path for top z level, or a ref to the turf above*/

//non-weatherproof turfs
/turf/var/weatherproof = TRUE
/turf/open/transparent/openspace/weatherproof = FALSE

/datum/lighting_corner/var/list/sunlight_objects /* list of sunlight objects affecting this corner */
/datum/lighting_corner/var/sunFalloff = 0 /* smallest distance to sunlight turf, for sunlight falloff */

/* loop through and find our strongest sunlight value */
/datum/lighting_corner/proc/get_sunlight_falloff()
	sunFalloff = 0
	for(var/atom/movable/outdoor_effect/S as anything in sunlight_objects)
		sunFalloff = max(sunlight_objects[S], sunFalloff)

/turf/proc/reassess_stack()
	if(!SSlighting.initialized)
		return

	/* remove roof refs (not path for psuedo roof) so we can recalculate it */
	if(pseudo_roof && !ispath(pseudo_roof))
		pseudo_roof = null

	//Add ourselves (we might not have corners initialized, and this handles it)
	GLOB.SUNLIGHT_QUEUE_WORK += src

	for(var/datum/lighting_corner/corner in corners)
		GLOB.SUNLIGHT_QUEUE_WORK |= corner.masters

	update_ceiling_status() // update here so that the turf below us, if it exists, can know our status ahead of time

	var/turf/T = GET_TURF_BELOW(src)
	if(T)
		T.reassess_stack()

/* check ourselves and neighbours to see what outdoor effects we need */
/* turf won't initialize an outdoor_effect if sky_blocked*/
/turf/proc/get_sky_and_weather_states()
	var/TempState

	var/roofStat = get_ceiling_status()
	if(roofStat["SKYVISIBLE"])
		TempState = SKY_VISIBLE
		var/tempRoofStat
		for(var/turf/CT in RANGE_TURFS(1, src) - src)
			tempRoofStat = CT.get_ceiling_status()
			if(!tempRoofStat?["SKYVISIBLE"]) /* if we have a single roofed/indoor neighbour, we are a border */
				TempState = SKY_VISIBLE_BORDER
				break
	else /* roofed, so turn off the lights */
		TempState = SKY_BLOCKED

	/* if border or indoor, initialize. Set sunlight state if valid */
	if(!outdoor_effect && (TempState == SKY_BLOCKED && roofStat["WEATHERPROOF"]))
		// Don't create a new outdoor effect if we're immune to both sun and weather
		return
	outdoor_effect ||= new /atom/movable/outdoor_effect(src) // Create a new weather effect if necessary
	outdoor_effect.state = TempState
	outdoor_effect.weatherproof = roofStat["WEATHERPROOF"]
	if(outdoor_effect.weatherproof)
		SSParticleWeather.weathered_turfs -= src
	else if(!(turf_flags & TURF_WEATHER_PROOF) && (z in SSoutdoor_effects.turf_weather_affectable_z_levels))
		SSParticleWeather.weathered_turfs |= src

/// Invalidates the cached ceiling status values so we're forced to generate new ones.
/turf/proc/invalidate_ceiling_status()
	if(outdoor_effect)
		// null -> no value cached, must generate
		outdoor_effect.state = null
		outdoor_effect.weatherproof = null

/// Like get_ceiling_status, but forces us to invalidate the cached values and generate new ones.
/turf/proc/update_ceiling_status()
	// invalidate our cached values
	invalidate_ceiling_status()
	// actually get and return the new values
	return get_ceiling_status()

/turf/proc/is_weatherproof()
	if(weatherproof)
		return TRUE
	for(var/obj/thing in src) // Checks to see if weatherproof objects on the tile
		if(thing.weatherproof)
			return TRUE

/* runs up the Z stack for this turf, returns a assoc (SKYVISIBLE, WEATHERPROOF)*/
/* pass as_ceiling=TRUE when we are checking our ceiling's stats */
/turf/proc/get_ceiling_status(as_ceiling = FALSE)
	// Check our cached values, ONLY WHEN NOT AS A CEILING
	if(!as_ceiling)
		var/our_state = outdoor_effect?.state
		var/our_weatherproof = outdoor_effect?.weatherproof
		if(!isnull(our_state) && !isnull(our_weatherproof))
			return list("SKYVISIBLE" = (our_state != SKY_BLOCKED), "WEATHERPROOF" = (our_weatherproof))

	// Start non-cached checks
	if(isopenturf(src) && !as_ceiling) //We are open, so assume open to the elements
		// for some reason, is_weatherproof() should only be checked when the turf is acting as a ceiling
		. = list("SKYVISIBLE" = TRUE, "WEATHERPROOF" = FALSE)
	else if(!istransparentturf(src))
		// Early leave if we can't see the sky - if we are an opaque turf, we already know the results
		// I can't think of a case where we would have a turf that would block light but let weather effects through - Maybe a vent?
		// fix this if that is the case
		return list("SKYVISIBLE" = FALSE, "WEATHERPROOF" = TRUE)
	else
		// This turf is either closed or acting as a ceiling
		. = list("SKYVISIBLE" = TRUE, "WEATHERPROOF" = is_weatherproof()) // check for weatherproof objects too

	//Ceiling Check
	var/area/turf_area = get_area(src)
	var/turf/above_turf = GET_TURF_ABOVE(src)
	// Psuedo-roof, for the top of the map (no actual turf exists up here) -- We assume these are solid, if you add glass pseudo_roofs then fix this
	if (pseudo_roof || (!above_turf && !turf_area.outdoors))
		return list("SKYVISIBLE" = FALSE, "WEATHERPROOF" = TRUE)
	// EVERY turf must be transparent for sunlight - so &=
	// ANY turf must be closed for weatherproof - so |=
	if(above_turf)
		var/list/ceilingStat = above_turf.get_ceiling_status(as_ceiling = TRUE) //Pass TRUE because we are now checking our ceilings
		if(!ceilingStat)
			return .
		.["SKYVISIBLE"]   &= ceilingStat["SKYVISIBLE"]
		.["WEATHERPROOF"] |= ceilingStat["WEATHERPROOF"]
