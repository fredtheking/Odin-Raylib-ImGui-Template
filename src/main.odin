package main

import "core:fmt"
import "core:strings"

// LIBRARIES
import rl "vendor:raylib"
import rlimgui "../lib/imgui_impl_raylib"
import imgui "../lib/odin-imgui"

main :: proc() {
    rl.SetConfigFlags({ rl.ConfigFlag.WINDOW_RESIZABLE, rl.ConfigFlag.WINDOW_ALWAYS_RUN })
    rl.InitWindow(800, 600, "Raylib + ImGui in Odin"); defer rl.CloseWindow()

    // Setup ImGui context
    imgui.CreateContext(nil); defer imgui.DestroyContext(nil)

    // Init ImGui for Raylib AND build font
    rlimgui.init(); defer rlimgui.shutdown()
    rlimgui.build_font_atlas()

    // Main loop
    for !rl.WindowShouldClose() {
        // Update logic (if needed)
        // ...

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        // ImGui begin (must be called each frame BEFORE using ImGui)
        rlimgui.begin()

        // Raylib rendering
        rl.DrawText("Drawing underneath ImGui window", 150, 300, 30, rl.RED)

        // ImGui buffering
        imgui.ShowDemoWindow(nil)

        // ImGui rendering
        rlimgui.end()

        // Drawing on top of ImGui (call after 'rlimgui.end()' to do that, as showed here)
        rl.DrawText("Drawing on top of ImGui window", 170, 370, 30, rl.BLUE)
        rl.EndDrawing()
    }
}
