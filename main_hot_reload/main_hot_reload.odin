// Development game exe. Loads game.dll and reloads it whenever it changes.

package main

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

Game_Update_And_Render_Proc :: #type proc() -> bool
Game_Init_Window_Proc :: #type proc()
Game_Init_Proc :: #type proc()
Game_Shutdown_Proc :: #type proc()
Game_Shutdown_Window_Proc :: #type proc()
Game_Memory_Proc :: #type proc() -> rawptr
Game_Memory_Size_Proc :: #type proc() -> int
Game_Hot_Reloaded_Proc :: #type proc(memory: rawptr)
Game_Force_Reload_Proc :: #type proc() -> bool
Game_Force_Restart_Proc :: #type proc() -> bool

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	exit: i32
	when ODIN_OS == .Windows {
		exit = libc.system(fmt.ctprintf("copy game.dll {0}", to))
	} else {
		exit = libc.system(fmt.ctprintf("cp game" + DLL_EXT + " {0}", to))
	}

	if exit != 0 {
		fmt.printfln("Failed to copy game" + DLL_EXT + " to {0}", to)
		return false
	}

	return true
}

Game_Code :: struct {
	lib:               dynlib.Library,
	modification_time: os.File_Time,
	api_version:       int,
	init_window:       Game_Init_Window_Proc,
	init:              Game_Init_Proc,
	update_and_render: Game_Update_And_Render_Proc,
	shutdown:          Game_Shutdown_Proc,
	shutdown_window:   Game_Shutdown_Window_Proc,
	memory:            Game_Memory_Proc,
	memory_size:       Game_Memory_Size_Proc,
	hot_reloaded:      Game_Hot_Reloaded_Proc,
	force_reload:      Game_Force_Reload_Proc,
	force_restart:     Game_Force_Restart_Proc,
}

load_game_api :: proc(api_version: int) -> (api: Game_Code, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name("game" + DLL_EXT)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of game" + DLL_EXT + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	// NOTE: this needs to be a relative path for Linux to work.
	game_dll_name := fmt.tprintf(
		"{0}game_{1}" + DLL_EXT,
		"./" when ODIN_OS != .Windows else "",
		api_version,
	)
	copy_dll(game_dll_name) or_return

	// This proc matches the names of the fields in Game_API to symbols in the
	// game DLL. It actually looks for symbols starting with `game_`, which is
	// why the argument `"game_"` is there.
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_Code) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf("game_{0}" + DLL_EXT, api.api_version)) != os.ERROR_NONE {
		fmt.printfln("Failed to remove game_{0}" + DLL_EXT + " copy", api.api_version)
	}
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	game_code_version := 0
	game_code, game_code_ok := load_game_api(game_code_version)

	if !game_code_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_code_version += 1
	game_code.init_window()
	game_code.init()

	old_game_codes := make([dynamic]Game_Code, default_allocator)

	window_open := true
	for window_open {
		window_open = game_code.update_and_render()
		force_reload := game_code.force_reload()
		force_restart := game_code.force_restart()
		reload := force_reload || force_restart
		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name("game" + DLL_EXT)

		if game_dll_mod_err == os.ERROR_NONE && game_code.modification_time != game_dll_mod {
			reload = true
		}

		if reload {
			new_game_code, new_game_code_ok := load_game_api(game_code_version)

			if new_game_code_ok {
				force_restart =
					force_restart || game_code.memory_size() != new_game_code.memory_size()

				if !force_restart {
					// This does the normal hot reload

					// Note that we don't unload the old game APIs because that
					// would unload the DLL. The DLL can contain stored info
					// such as string literals. The old DLLs are only unloaded
					// on a full reset or on shutdown.
					append(&old_game_codes, game_code)
					game_memory := game_code.memory()
					game_code = new_game_code
					game_code.hot_reloaded(game_memory)
				} else {
					// This does a full reset. That's basically like opening and
					// closing the game, without having to restart the executable.
					//
					// You end up in here if the game requests a full reset OR
					// if the size of the game memory has changed. That would
					// probably lead to a crash anyways.

					game_code.shutdown()
					reset_tracking_allocator(&tracking_allocator)

					for &g in old_game_codes {
						unload_game_api(&g)
					}

					clear(&old_game_codes)
					unload_game_api(&game_code)
					game_code = new_game_code
					game_code.init()
				}

				game_code_version += 1
			}
		}

		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}

			// This prevents the game from closing without you seeing the bad
			// frees. This is mostly needed because I use Sublime Text and my game's
			// console isn't hooked up into Sublime's console properly.
			libc.getchar()
			panic("Bad free detected")
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_code.shutdown()
	if reset_tracking_allocator(&tracking_allocator) {
		// This prevents the game from closing without you seeing the memory
		// leaks. This is mostly needed because I use Sublime Text and my game's
		// console isn't hooked up into Sublime's console properly.
		libc.getchar()
	}

	for &g in old_game_codes {
		unload_game_api(&g)
	}

	delete(old_game_codes)

	game_code.shutdown_window()
	unload_game_api(&game_code)
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
