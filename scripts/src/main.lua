-- license:BSD-3-Clause
-- copyright-holders:MAMEdev Team

---------------------------------------------------------------------------
--
--   main.lua
--
--   Rules for building main binary
--
---------------------------------------------------------------------------

function mainProject(_target, _subtarget)
local projname
if (_OPTIONS["SOURCES"] == nil) and (_OPTIONS["SOURCEFILTER"] == nil) then
	if (_target == _subtarget) then
		projname = _target
	else
		projname = _target .. _subtarget
	end
else
	projname = _subtarget
end
	project (projname)
	uuid (os.uuid(_target .. "_" .. _subtarget))
	kind "ConsoleApp"

	configuration { "android*" }
if _OPTIONS["osd"] == "retro" then
		linkoptions {
			"-shared",
		}
else
		targetprefix "lib"
		targetname "main"
		targetextension ".so"
		linkoptions {
			"-shared",
			"-Wl,-soname,libmain.so"
		}
end
		links {
			"EGL",
			"GLESv1_CM",
			"GLESv2",
-- RETRO HACK no sdl for libretro android
--			"SDL2",
		}
if _OPTIONS["osd"] == "retro" then

else
               links {
                        "SDL2",
                }
end
-- RETRO HACK END no sdl for libretro android

	configuration {  }

	addprojectflags()
	flags {
		"NoManifest",
		--"Symbols", -- always include minimum symbols for executables, or maybe not, since it wastes space and needs stripping after
	}

	if _OPTIONS["SYMBOLS"] then
		configuration { "mingw*" }
			postbuildcommands {
				--"$(SILENT) echo Dumping symbols.",
				--"$(SILENT) objdump --section=.text --line-numbers --syms --demangle $(TARGET) >$(subst .exe,.sym,$(TARGET))"
			}
	end

	configuration { "Release" }
		targetsuffix ""
		if _OPTIONS["PROFILE"] then
			targetsuffix "p"
		end

	configuration { "Debug" }
		targetsuffix "d"
		if _OPTIONS["PROFILE"] then
			targetsuffix "dp"
		end

	configuration { "mingw*" or "vs20*" }
		targetextension ".exe"

	configuration { "asmjs" }
		targetextension ".bc"
-- RETRO HACK no sdl for libretro android
if _OPTIONS["osd"] == "retro" then


else
		if os.getenv("EMSCRIPTEN") then
			local emccopts = ""
				.. " -O" .. _OPTIONS["OPTIMIZE"]
				.. " -s USE_SDL=2"
				.. " -s USE_SDL_TTF=2"
				.. " --memory-init-file 0"
				.. " -s DISABLE_EXCEPTION_CATCHING=2"
				.. " -s EXCEPTION_CATCHING_WHITELIST=\"['__ZN15running_machine17start_all_devicesEv','__ZN12cli_frontend7executeEiPPc','__ZN8chd_file11open_commonEb','__ZN8chd_file13read_metadataEjjRNSt3__212basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE','__ZN8chd_file13read_metadataEjjRNSt3__26vectorIhNS0_9allocatorIhEEEE','__ZNK19netlist_mame_device19base_validity_checkER16validity_checker']\""
				.. " -s EXPORTED_FUNCTIONS=\"['_main', '_malloc', '__ZN15running_machine30emscripten_get_running_machineEv', '__ZN15running_machine17emscripten_get_uiEv', '__ZN15running_machine20emscripten_get_soundEv', '__ZN15mame_ui_manager12set_show_fpsEb', '__ZNK15mame_ui_manager8show_fpsEv', '__ZN13sound_manager4muteEbh', '_SDL_PauseAudio', '_SDL_SendKeyboardKey', '__ZN15running_machine15emscripten_saveEPKc', '__ZN15running_machine15emscripten_loadEPKc', '__ZN15running_machine21emscripten_hard_resetEv', '__ZN15running_machine21emscripten_soft_resetEv', '__ZN15running_machine15emscripten_exitEv']\""
				.. " -s EXTRA_EXPORTED_RUNTIME_METHODS=\"['cwrap']\""
				.. " -s ERROR_ON_UNDEFINED_SYMBOLS=0"
				.. " -s USE_WEBGL2=1"
				.. " -s LEGACY_GL_EMULATION=1"
				.. " -s GL_UNSAFE_OPTS=0"
				.. " --pre-js " .. _MAKE.esc(MAME_DIR) .. "src/osd/modules/sound/js_sound.js"
				.. " --post-js " .. _MAKE.esc(MAME_DIR) .. "scripts/resources/emscripten/emscripten_post.js"
				.. " --embed-file " .. _MAKE.esc(MAME_DIR) .. "bgfx/chains@bgfx/chains"
				.. " --embed-file " .. _MAKE.esc(MAME_DIR) .. "bgfx/effects@bgfx/effects"
				.. " --embed-file " .. _MAKE.esc(MAME_DIR) .. "bgfx/shaders/essl@bgfx/shaders/essl"
				.. " --embed-file " .. _MAKE.esc(MAME_DIR) .. "artwork/bgfx@artwork/bgfx"
				.. " --embed-file " .. _MAKE.esc(MAME_DIR) .. "artwork/slot-mask.png@artwork/slot-mask.png"

			if _OPTIONS["SYMBOLS"]~=nil and _OPTIONS["SYMBOLS"]~="0" then
				emccopts = emccopts
					.. " -g" .. _OPTIONS["SYMLEVEL"]
					.. " -s DEMANGLE_SUPPORT=1"
			end

			if _OPTIONS["WEBASSEMBLY"] then
				emccopts = emccopts
					.. " -s WASM=" .. _OPTIONS["WEBASSEMBLY"]
			else
				emccopts = emccopts
					.. " -s WASM=1"
			end

			if _OPTIONS["WEBASSEMBLY"]~=nil and _OPTIONS["WEBASSEMBLY"]=="0" then
				-- define a fixed memory size because allowing memory growth disables asm.js optimizations
				emccopts = emccopts
					.. " -s ALLOW_MEMORY_GROWTH=0"
					.. " -s TOTAL_MEMORY=268435456"
			else
				emccopts = emccopts
					.. " -s ALLOW_MEMORY_GROWTH=1"
			end

			if _OPTIONS["ARCHOPTS"] then
				emccopts = emccopts .. " " .. _OPTIONS["ARCHOPTS"]
			end

			postbuildcommands {
				--os.getenv("EMSCRIPTEN") .. "/emcc " .. emccopts .. " $(TARGET) -o " .. _MAKE.esc(MAME_DIR) .. _OPTIONS["target"] .. _OPTIONS["subtarget"] .. ".js",
				os.getenv("EMSCRIPTEN") .. "/emcc " .. emccopts .. " $(TARGET) -o " .. _MAKE.esc(MAME_DIR) .. _OPTIONS["target"] .. _OPTIONS["subtarget"] .. ".html",
			}
		end

		targetextension ".html"
end
	-- BEGIN libretro overrides to MAME's GENie build
	configuration { "libretro*" }
		kind "SharedLib"	
		targetsuffix "_libretro"
		if _OPTIONS["targetos"]=="android" then
			targetsuffix "_libretro_android"
			defines {
 				"SDLMAME_ARM=1",
			}
		elseif _OPTIONS["targetos"]=="asmjs" then
			targetsuffix "_libretro_emscripten"
			linkoptions {
				 "-s DISABLE_EXCEPTION_CATCHING=2",
				 "-s EXCEPTION_CATCHING_WHITELIST='[\"__ZN15running_machine17start_all_devicesEv\",\"__ZN12cli_frontend7executeEiPPc\"]'",			}
		elseif _OPTIONS["targetos"]=="ios-arm" or _OPTIONS["LIBRETRO_IOS"]=="1" then
			targetsuffix "_libretro_ios"
			targetextension ".dylib"
		elseif _OPTIONS["LIBRETRO_TVOS"]=="1" then
			targetsuffix "_libretro_tvos"
			targetextension ".dylib"
		elseif _OPTIONS["targetos"]=="windows" then
			targetextension ".dll"
			flags {
				"NoImportLib",
			}
		elseif _OPTIONS["targetos"]=="osx" then
			targetextension ".dylib"
		else
			targetsuffix "_libretro"
		end

		targetprefix ""

		includedirs {
			MAME_DIR .. "src/osd/libretro/libretro-internal",
		}

		files {
			MAME_DIR .. "src/osd/libretro/libretro-internal/libretro.cpp"
		}

		-- Ensure the public API is made public with GNU ld
		if _OPTIONS["targetos"]=="linux" then
			linkoptions {
				"-Wl,--version-script=" .. MAME_DIR .. "src/osd/libretro/libretro-internal/link.T",
			}
		end

	-- END libretro overrides to MAME's GENie build
	configuration { }

	if _OPTIONS["targetos"]=="android" then

-- RETRO HACK no sdl for libretro android
if _OPTIONS["osd"] == "retro" then

		if _OPTIONS["SEPARATE_BIN"]~="1" then
			targetdir(MAME_DIR)
		end
else
		includedirs {
			MAME_DIR .. "3rdparty/SDL2/include",
		}

		files {
			MAME_DIR .. "src/osd/sdl/android_main.cpp",
		}

		targetsuffix ""
		if _OPTIONS["SEPARATE_BIN"]~="1" then
			if _OPTIONS["PLATFORM"]=="arm" then
				targetdir(MAME_DIR .. "android-project/app/src/main/libs/armeabi-v7a")
				os.copyfile(_OPTIONS["SDL_INSTALL_ROOT"] .. "/lib/libSDL2.so", MAME_DIR .. "android-project/app/src/main/libs/armeabi-v7a/libSDL2.so")
				os.copyfile(androidToolchainRoot() .. "/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so", MAME_DIR .. "android-project/app/src/main/libs/armeabi-v7a/libc++_shared.so")
			end
			if _OPTIONS["PLATFORM"]=="arm64" then
				targetdir(MAME_DIR .. "android-project/app/src/main/libs/arm64-v8a")
				os.copyfile(_OPTIONS["SDL_INSTALL_ROOT"] .. "/lib/libSDL2.so", MAME_DIR .. "android-project/app/src/main/libs/arm64-v8a/libSDL2.so")
				os.copyfile(androidToolchainRoot() .. "/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so", MAME_DIR .. "android-project/app/src/main/libs/arm64-v8a/libc++_shared.so")
			end
			if _OPTIONS["PLATFORM"]=="x86" then
				targetdir(MAME_DIR .. "android-project/app/src/main/libs/x86")
				os.copyfile(_OPTIONS["SDL_INSTALL_ROOT"] .. "/lib/libSDL2.so", MAME_DIR .. "android-project/app/src/main/libs/x86/libSDL2.so")
				os.copyfile(androidToolchainRoot() .. "/sysroot/usr/lib/i686-linux-android/libc++_shared.so", MAME_DIR .. "android-project/app/src/main/libs/x86/libc++_shared.so")
			end
			if _OPTIONS["PLATFORM"]=="x64" then
				targetdir(MAME_DIR .. "android-project/app/src/main/libs/x86_64")
				os.copyfile(_OPTIONS["SDL_INSTALL_ROOT"] .. "/lib/libSDL2.so", MAME_DIR .. "android-project/app/src/main/libs/x86_64/libSDL2.so")
				os.copyfile(androidToolchainRoot() .. "/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so", MAME_DIR .. "android-project/app/src/main/libs/x86_64/libc++_shared.so")
			end
		end
end
-- RETRO HACK END no sdl for libretro android
	else
		if _OPTIONS["SEPARATE_BIN"]~="1" then
			targetdir(MAME_DIR)
		end
	end

if (STANDALONE~=true) then
	findfunction("linkProjects_" .. _OPTIONS["target"] .. "_" .. _OPTIONS["subtarget"])(_OPTIONS["target"], _OPTIONS["subtarget"])
end
if (STANDALONE~=true) then
	links {
		"frontend",
	}
end
	links {
		"optional",
		"emu",
	}
	links {
		"osd_" .. _OPTIONS["osd"],
	}
-- RETRO HACK no qt
if _OPTIONS["osd"]=="retro" then

else
	links {
		"qtdbg_" .. _OPTIONS["osd"],
	}
end
-- RETRO HACK END

--if (STANDALONE~=true) then
	links {
		"formats",
	}
--end
if #disasm_files > 0 then
	links {
		"dasm",
	}
end
if (MACHINES["NETLIST"]~=null) then
	links {
		"netlist",
	}
end
	links {
		"utils",
		ext_lib("expat"),
		"softfloat",
		"softfloat3",
		"wdlfft",
		"ymfm",
		ext_lib("jpeg"),
		"7z",
	}
if CPU_INCLUDE_DRC_NATIVE then
	links {
		"asmjit",
	}
end
if (STANDALONE~=true) then
	links {
		ext_lib("lua"),
		"lualibs",
		"linenoise",
	}
end
	links {
		ext_lib("zlib"),
		ext_lib("zstd"),
		ext_lib("flac"),
		ext_lib("utf8proc"),
	}
if (STANDALONE~=true) then
	links {
		ext_lib("sqlite3"),
	}
end

	if _OPTIONS["NO_USE_PORTAUDIO"]~="1" then
		links {
			ext_lib("portaudio"),
		}
		if _OPTIONS["targetos"]=="windows" then
			links {
				"setupapi",
			}
		end
	end
	if _OPTIONS["NO_USE_MIDI"]~="1" then
		links {
			ext_lib("portmidi"),
		}
	end
	if _OPTIONS["NO_USE_BGFX"]~="1" then
		links {
			"bgfx",
			"bimg",
			"bx",
		}
	end
	links {
		"ocore_" .. _OPTIONS["osd"],
	}

	override_resources = false;

	maintargetosdoptions(_target, _subtarget)
	local exename = projname -- FIXME: should include the OSD prefix if any

	includedirs {
		MAME_DIR .. "src/osd",
		MAME_DIR .. "src/emu",
		MAME_DIR .. "src/devices",
		MAME_DIR .. "src/" .. _target,
		MAME_DIR .. "src/lib",
		MAME_DIR .. "src/lib/util",
		MAME_DIR .. "3rdparty",
		GEN_DIR  .. _target .. "/layout",
		ext_includedir("zlib"),
		ext_includedir("flac"),
	}

	resincludedirs {
		MAME_DIR .. "scripts/resources/windows/" .. _target,
		GEN_DIR  .. "resource",
	}

	-- RETRO HACK
	if _OPTIONS["osd"]=="retro" then
 
       forcedincludes {
			MAME_DIR .. "src/osd/libretro/retroprefix.h"
		}

		includedirs {
			MAME_DIR .. "src/emu",
			MAME_DIR .. "src/osd",
			MAME_DIR .. "src/lib",
			MAME_DIR .. "src/lib/util",
			MAME_DIR .. "src/osd/libretro",
			MAME_DIR .. "src/osd/interface",
			MAME_DIR .. "src/osd/modules/render",
			MAME_DIR .. "3rdparty",
			MAME_DIR .. "3rdparty/bgfx/include",
			MAME_DIR .. "3rdparty/bx/include",
			MAME_DIR .. "src/osd/libretro/libretro-internal",
		}

  	if _OPTIONS["targetos"]=="windows" then
  		includedirs {
  			MAME_DIR .. "3rdparty/winpcap/Include",
		}
	end

		files {
			MAME_DIR .. "src/osd/libretro/retromain.cpp",
			MAME_DIR .. "src/osd/libretro/libretro-internal/libretro.cpp",
		}
	end
-- RETRO HACK
if (STANDALONE==true) then
	standalone();
end

if (STANDALONE~=true) then
	if _OPTIONS["targetos"]=="macosx" and (not override_resources) and not (_OPTIONS["LIBRETRO_IOS"]=="1" or _OPTIONS["LIBRETRO_TVOS"]=="1") then
		local plistname = _target .. "_" .. _subtarget .. "-Info.plist"
		linkoptions {
			"-sectcreate __TEXT __info_plist " .. _MAKE.esc(GEN_DIR) .. "resource/" .. plistname
		}
		custombuildtask {
			{
				GEN_DIR .. "version.cpp",
				GEN_DIR .. "resource/" .. plistname,
				{ MAME_DIR .. "scripts/build/verinfo.py" },
				{
					"@echo Emitting " .. plistname .. "...",
					PYTHON .. " $(1) -f plist -t " .. _target .. " -s " .. _subtarget .. " -e " .. exename .. " -o $(@) $(<)"
				}
			},
		}
		dependency {
			{ "$(TARGET)" ,  GEN_DIR  .. "resource/" .. plistname, true },
		}

	end

	local rcversfile = GEN_DIR .. "resource/" .. _target .. "_" .. _subtarget .. "_vers.rc"
	if _OPTIONS["targetos"]=="windows" and (not override_resources) then
		files {
			rcversfile
		}
	end

	local rcincfile = MAME_DIR .. "scripts/resources/windows/" .. _target .. "/" .. _subtarget ..".rc"
	if not os.isfile(rcincfile) then
		rcincfile = MAME_DIR .. "scripts/resources/windows/mame/mame.rc"
		resincludedirs {
			MAME_DIR .. "scripts/resources/windows/mame",
		}
	end

	local mainfile = MAME_DIR .. "src/" .. _target .. "/" .. _subtarget .. ".cpp"
	if not os.isfile(mainfile) then
		mainfile = MAME_DIR .. "src/" .. _target .. "/" .. _target .. ".cpp"
	end
	files {
		mainfile,
		GEN_DIR .. "version.cpp",
		GEN_DIR .. _target .. "/" .. _subtarget .. "/drivlist.cpp",
	}

	local driverlist = MAME_DIR .. "src/" .. _target .. "/" .. _target .. ".lst"
	local driverssrc = GEN_DIR .. _target .. "/" .. _subtarget .. "/drivlist.cpp"
	if _OPTIONS["SOURCES"] ~= nil then
		dependency {
			{ driverssrc, driverlist, true },
		}
		custombuildtask {
			{
				GEN_DIR .. _target .."/" .. _subtarget .. ".flt" ,
				driverssrc,
				{ MAME_DIR .. "scripts/build/makedep.py", driverlist },
				{
					"@echo Building driver list...",
					PYTHON .. " $(1) -r " .. MAME_DIR .. " driverlist $(2) -f $(<) > $(@)"
				}
			},
		}
	elseif _OPTIONS["SOURCEFILTER"] ~= nil then
		dependency {
			{ driverssrc, driverlist, true },
		}
		custombuildtask {
			{
				MAME_DIR .. _OPTIONS["SOURCEFILTER"],
				driverssrc,
				{ MAME_DIR .. "scripts/build/makedep.py", driverlist },
				{
					"@echo Building driver list...",
					PYTHON .. " $(1) -r " .. MAME_DIR .. " driverlist $(2) -f $(<) > $(@)"
				}
			},
		}
	elseif os.isfile(MAME_DIR .. "src/" .. _target .."/" .. _subtarget ..".flt") then
		dependency {
			{ driverssrc, driverlist, true },
		}
		custombuildtask {
			{
				MAME_DIR .. "src/" .. _target .. "/" .. _subtarget .. ".flt",
				driverssrc,
				{ MAME_DIR .. "scripts/build/makedep.py", driverlist },
				{
					"@echo Building driver list...",
					PYTHON .. " $(1) -r " .. MAME_DIR .. " driverlist $(2) -f $(<) > $(@)"
				}
			},
		}
	elseif os.isfile(MAME_DIR .. "src/" .._target .. "/" .. _subtarget ..".lst") then
		custombuildtask {
			{
				MAME_DIR .. "src/" .. _target .. "/" .. _subtarget .. ".lst",
				driverssrc,
				{ MAME_DIR .. "scripts/build/makedep.py" },
				{
					"@echo Building driver list...",
					PYTHON .. " $(1) -r " .. MAME_DIR .. " driverlist $(<) > $(@)"
				}
			},
		}
	else
		dependency {
			{ driverssrc, driverlist, true },
		}
		custombuildtask {
			{
				driverlist,
				driverssrc,
				{ MAME_DIR .. "scripts/build/makedep.py" },
				{
					"@echo Building driver list...",
					PYTHON .. " $(1) -r " .. MAME_DIR .. " driverlist $(<) > $(@)"
				}
			},
		}
	end

	configuration { "mingw*" }
		dependency {
			{ "$(OBJDIR)/" .. _target .. "_" .. _subtarget .. "_vers.res", rcincfile, true },
		}
		custombuildtask {
			{
				GEN_DIR .. "version.cpp" ,
				rcversfile,
				{ MAME_DIR .. "scripts/build/verinfo.py" },
				{
					"@echo Emitting " .. _target .. "_" .. _subtarget .. "_vers.rc" .. "...",
					PYTHON .. " $(1) -f rc -t " .. _target .. " -s " .. _subtarget .. " -e " .. exename .. " -r " .. path.getname(rcincfile) .. " -o $(@) $(<)"
				}
			},
		}

	configuration { "vs20*" }
		dependency {
			{ "$(OBJDIR)/" .. _target .. "_" .. _subtarget .. "_vers.res", rcincfile, true },
		}
		prebuildcommands {
			"mkdir \"" .. path.translate(GEN_DIR .. "resource/", "\\") .. "\" 2>NUL",
			"mkdir \"" .. path.translate(GEN_DIR .. _target .. "/" .. _subtarget .. "/", "\\") .. "\" 2>NUL",
			"@echo Emitting " .. _target .. "_" .. _subtarget .. "_vers.rc" .. "...",
			PYTHON .. " \"" .. path.translate(MAME_DIR .. "scripts/build/verinfo.py", "\\") .. "\" -f rc -t " .. _target .. " -s " .. _subtarget .. " -e " .. exename .. " -o \"" .. path.translate(rcversfile) .. "\" -r \"" .. path.getname(rcincfile) .. "\" \"" .. path.translate(GEN_DIR .. "version.cpp", "\\") .. "\"",
		}
end

	configuration { }

	if _OPTIONS["DEBUG_DIR"]~=nil then
		debugdir(_OPTIONS["DEBUG_DIR"])
	else
		debugdir (MAME_DIR)
	end
	if _OPTIONS["DEBUG_ARGS"]~=nil then
		debugargs (_OPTIONS["DEBUG_ARGS"])
	else
		debugargs ("-window")
	end

end
