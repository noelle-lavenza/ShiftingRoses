// Like basic space but doesn't have the space plane.
/turf/closed/dark_filler
	name = "\proper nothing"
	icon = 'icons/turf/space.dmi'
	icon_state = "black"
	baseturfs = /turf/closed/dark_filler

/turf/closed/dark_filler/New()	//Do not convert to Initialize
	SHOULD_CALL_PARENT(FALSE)
	//This is used to optimize the map loader
	return

/turf/closed/dark_filler/Initialize()
	SHOULD_CALL_PARENT(FALSE)
	if(flags_1 & INITIALIZED_1)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	//let's not and say we did
	flags_1 |= INITIALIZED_1
	// except for this because it makes stuff runtime if we skip it
	SETUP_SMOOTHING()
	return INITIALIZE_HINT_NORMAL

// These procs should never do anything.
/turf/closed/dark_filler/get_sky_and_weather_states()
	return
/turf/closed/dark_filler/get_ceiling_status(as_ceiling)
	return
