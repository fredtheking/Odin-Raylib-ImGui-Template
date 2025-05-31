package imgui_impl_raylib

// Based on the raylib extras rlImGui: https://github.com/raylib-extras/rlImGui/blob/main/rlImGui.cpp
/* Usage:

import imgui_rl "imgui_impl_raylib"
import imgui "../../odin-imgui"

main :: proc() {
    rl.SetConfigFlags({ rl.ConfigFlag.WINDOW_RESIZABLE })
    rl.InitWindow(800, 600, "raylib basic window")
    defer rl.CloseWindow()

    imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)

    imgui_rl.init()
	defer imgui_rl.shutdown()

    imgui_rl.build_font_atlas()

    for !rl.WindowShouldClose() {
		imgui_rl.process_events()
		imgui_rl.new_frame()
		imgui.NewFrame()

        rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

        imgui.ShowDemoWindow(nil)

        imgui.Render()
		imgui_rl.render_draw_data(imgui.GetDrawData())

        rl.EndDrawing()
    }
}
*/

import "core:c"
import "core:mem"
import "core:math"

// Follow build instruction for imgui bindings in: https://gitlab.com/L-4/odin-imgui
import imgui "../odin-imgui"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

current_mouse_cursor: imgui.MouseCursor = imgui.MouseCursor.COUNT
mouse_cursor_map: [imgui.MouseCursor.COUNT]rl.MouseCursor

last_frame_focused := false
last_control_pressed := false
last_shift_pressed := false
last_alt_pressed := false
last_super_pressed := false

raylib_key_map: map[rl.KeyboardKey]imgui.Key = {}

init :: proc() -> bool {
    setup_globals()
    setup_keymap()
    setup_mouse_cursor()
    setup_backend()

    return true
}

build_font_atlas :: proc() -> mem.Allocator_Error {
    io: ^imgui.IO = imgui.GetIO()

    pixels: ^c.uchar
    width, height: c.int
    imgui.FontAtlas_GetTexDataAsRGBA32(io.Fonts, &pixels, &width, &height, nil)
    image: rl.Image = rl.GenImageColor(width, height, rl.BLANK)
    mem.copy(image.data, pixels, int(width * height * 4))

    font_texture: ^rl.Texture2D = transmute(^rl.Texture)io.Fonts.TexID
    if font_texture != nil && font_texture.id != 0 {
        rl.UnloadTexture(font_texture^)
        mem.free(font_texture)
    }

    font_texture = cast(^rl.Texture2D)(mem.alloc(size_of(rl.Texture2D), align_of(rl.Texture2D)) or_return)
    font_texture^ = rl.LoadTextureFromImage(image)
    rl.UnloadImage(image)
    io.Fonts.TexID = font_texture

    return nil
}

shutdown :: proc() {
    io: ^imgui.IO = imgui.GetIO()
    font_texture: ^rl.Texture2D = transmute(^rl.Texture)io.Fonts.TexID

    if font_texture != nil && font_texture.id != 0 {
        rl.UnloadTexture(font_texture^)
        mem.free(font_texture)
    }

    io.Fonts.TexID = nil
}

begin :: proc(){
    process_events()
    new_frame()
    imgui.NewFrame()
}

end :: proc(){
    imgui.Render()
    render_draw_data(imgui.GetDrawData())
}

new_frame :: proc() {
    io: ^imgui.IO = imgui.GetIO()

    if rl.IsWindowFullscreen() {
        monitor := rl.GetCurrentMonitor()
        io.DisplaySize.x = f32(rl.GetMonitorWidth(monitor))
        io.DisplaySize.y = f32(rl.GetMonitorHeight(monitor))
    } else {
        io.DisplaySize.x = f32(rl.GetScreenWidth())
        io.DisplaySize.y = f32(rl.GetScreenHeight())
    }

    io.DisplayFramebufferScale = rl.GetWindowScaleDPI()
    io.DeltaTime = rl.GetFrameTime()

    if io.WantSetMousePos {
        rl.SetMousePosition(c.int(io.MousePos.x), c.int(io.MousePos.y))
    } else {
        mouse_pos := rl.GetMousePosition()
        imgui.IO_AddMousePosEvent(io, mouse_pos.x, mouse_pos.y)
    }

    set_mouse_event :: proc(io: ^imgui.IO, rl_mouse: rl.MouseButton, imgui_mouse: c.int) {
        if rl.IsMouseButtonPressed(rl_mouse) {
            imgui.IO_AddMouseButtonEvent(io, imgui_mouse, true)
        } else if rl.IsMouseButtonReleased(rl_mouse) {
            imgui.IO_AddMouseButtonEvent(io, imgui_mouse, false)
        }
    }

    set_mouse_event(io, rl.MouseButton.LEFT, c.int(imgui.MouseButton.Left))
    set_mouse_event(io, rl.MouseButton.RIGHT, c.int(imgui.MouseButton.Right))
    set_mouse_event(io, rl.MouseButton.MIDDLE, c.int(imgui.MouseButton.Middle))
    set_mouse_event(io, rl.MouseButton.FORWARD, c.int(imgui.MouseButton.Middle) + 1)
    set_mouse_event(io, rl.MouseButton.BACK, c.int(imgui.MouseButton.Middle) + 2)

    mouse_wheel := rl.GetMouseWheelMoveV()
    imgui.IO_AddMouseWheelEvent(io, mouse_wheel.x, mouse_wheel.y)

    if imgui.ConfigFlag.NoMouseCursorChange not_in io.ConfigFlags {
        imgui_cursor: imgui.MouseCursor = imgui.GetMouseCursor()
        if imgui_cursor != current_mouse_cursor || io.MouseDrawCursor {
            current_mouse_cursor = imgui_cursor
            if io.MouseDrawCursor || imgui_cursor == imgui.MouseCursor.None {
                rl.HideCursor()
            } else {
                rl.ShowCursor()
                if c.int(imgui_cursor) > -1 && imgui_cursor < imgui.MouseCursor.COUNT {
                    rl.SetMouseCursor(mouse_cursor_map[imgui_cursor])
                } else {
                    rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
                }
            }
        }
    }
}

render_draw_data :: proc(draw_data: ^imgui.DrawData) {
    rlgl.DrawRenderBatchActive()
    rlgl.DisableBackfaceCulling()

    command_lists: []^imgui.DrawList = mem.slice_ptr(draw_data.CmdLists.Data, int(draw_data.CmdLists.Size))
    for command_list in command_lists {
        cmd_slice: []imgui.DrawCmd = mem.slice_ptr(command_list.CmdBuffer.Data, int(command_list.CmdBuffer.Size))
        for i in 0..<command_list.CmdBuffer.Size {
            cmd := cmd_slice[i]
            enable_scissor(
            cmd.ClipRect.x - draw_data.DisplayPos.x,
            cmd.ClipRect.y,
            cmd.ClipRect.z - (cmd.ClipRect.x - draw_data.DisplayPos.x),
            cmd.ClipRect.w - (cmd.ClipRect.y - draw_data.DisplayPos.y)
            )

            if cmd.UserCallback != nil {
                cmd.UserCallback(command_list, &cmd)
                continue
            }

            render_triangles(cmd.ElemCount, cmd.IdxOffset, command_list.IdxBuffer, command_list.VtxBuffer, cmd.TextureId)
            rlgl.DrawRenderBatchActive()
        }
    }

    rlgl.SetTexture(0)
    rlgl.DisableScissorTest()
    rlgl.EnableBackfaceCulling()
}

@private
enable_scissor :: proc(x: f32, y: f32, width: f32, height: f32) {
    rlgl.EnableScissorTest()
    io: ^imgui.IO = imgui.GetIO()

    rlgl.Scissor(
    i32(x * io.DisplayFramebufferScale.x),
    i32((io.DisplaySize.y - math.floor(y + height)) * io.DisplayFramebufferScale.y),
    i32(width * io.DisplayFramebufferScale.x),
    i32(height * io.DisplayFramebufferScale.y)
    )
}

@private
render_triangles :: proc(count: u32, index_start: u32, index_buffer: imgui.Vector_DrawIdx, vert_buffer: imgui.Vector_DrawVert, texture_ptr: imgui.TextureID) {
    if count < 3 {
        return
    }

    texture: ^rl.Texture = transmute(^rl.Texture)texture_ptr

    texture_id: u32 = (texture == nil) ? 0 : texture.id

    rlgl.Begin(rlgl.TRIANGLES)
    rlgl.SetTexture(texture_id)

    index_slice: []imgui.DrawIdx = mem.slice_ptr(index_buffer.Data, int(index_buffer.Size))
    vert_slice: []imgui.DrawVert = mem.slice_ptr(vert_buffer.Data, int(vert_buffer.Size))

    for i: u32 = 0; i <= (count - 3); i += 3 {
        if rlgl.CheckRenderBatchLimit(3) != 0 {
            rlgl.Begin(rlgl.TRIANGLES)
            rlgl.SetTexture(texture_id)
        }

        index_a := index_slice[index_start + i]
        index_b := index_slice[index_start + i + 1]
        index_c := index_slice[index_start + i + 2]

        vertex_a := vert_slice[index_a]
        vertex_b := vert_slice[index_b]
        vertex_c := vert_slice[index_c]

        draw_triangle_vert :: proc(vert: imgui.DrawVert) {
            c: rl.Color = transmute(rl.Color)vert.col
            rlgl.Color4ub(c.r, c.g, c.b, c.a)
            rlgl.TexCoord2f(vert.uv.x, vert.uv.y)
            rlgl.Vertex2f(vert.pos.x, vert.pos.y)
        }

        draw_triangle_vert(vertex_a)
        draw_triangle_vert(vertex_b)
        draw_triangle_vert(vertex_c)
    }

    rlgl.End()
}

is_control_down :: proc() -> bool { return rl.IsKeyDown(rl.KeyboardKey.RIGHT_CONTROL) || rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL); }
is_shift_down :: proc() -> bool { return rl.IsKeyDown(rl.KeyboardKey.RIGHT_SHIFT) || rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT); }
is_alt_down :: proc() -> bool { return rl.IsKeyDown(rl.KeyboardKey.RIGHT_ALT) || rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT); }
is_super_down :: proc() -> bool { return rl.IsKeyDown(rl.KeyboardKey.RIGHT_SUPER) || rl.IsKeyDown(rl.KeyboardKey.LEFT_SUPER); }

process_events :: proc() -> bool {
    io: ^imgui.IO = imgui.GetIO()

    focused := rl.IsWindowFocused()
    if (focused != last_frame_focused) {
        imgui.IO_AddFocusEvent(io, focused)
    }
    last_frame_focused = focused

    // Handle modifers for key evets so that shortcuts work
    ctrl_down := is_control_down()
    if ctrl_down != last_control_pressed {
        imgui.IO_AddKeyEvent(io, imgui.Key.ImGuiMod_Ctrl, ctrl_down)
    }
    last_control_pressed = ctrl_down

    shift_down := is_shift_down()
    if shift_down != last_shift_pressed {
        imgui.IO_AddKeyEvent(io, imgui.Key.ImGuiMod_Shift, shift_down)
    }
    last_shift_pressed = shift_down

    alt_down := is_alt_down()
    if alt_down != last_alt_pressed {
        imgui.IO_AddKeyEvent(io, imgui.Key.ImGuiMod_Alt, alt_down)
    }
    last_alt_pressed = alt_down

    super_down := is_super_down()
    if super_down != last_super_pressed {
        imgui.IO_AddKeyEvent(io, imgui.Key.ImGuiMod_Super, super_down)
    }
    last_super_pressed = super_down

    // Get pressed keys, they are in event order
    key_id: rl.KeyboardKey = rl.GetKeyPressed()
    for key_id != rl.KeyboardKey.KEY_NULL {
        key, ok := raylib_key_map[key_id]
        if ok {
            imgui.IO_AddKeyEvent(io, key, true)
        }

        key_id = rl.GetKeyPressed()
    }

    // Check for released keys
    for key in raylib_key_map {
        if rl.IsKeyReleased(key) {
            imgui.IO_AddKeyEvent(io, raylib_key_map[key], false)
        }
    }

    // Add text input in order
    pressed: rune = rl.GetCharPressed()
    for pressed != 0 {
        imgui.IO_AddInputCharacter(io, u32(pressed))
        pressed = rl.GetCharPressed()
    }

    return true
}

@private
setup_globals :: proc() {
    last_frame_focused = rl.IsWindowFocused()
    last_control_pressed = false
    last_shift_pressed = false
    last_alt_pressed = false
    last_super_pressed = false
}

@private
setup_keymap :: proc() {
    raylib_key_map[rl.KeyboardKey.APOSTROPHE] = imgui.Key.Apostrophe
    raylib_key_map[rl.KeyboardKey.COMMA] = imgui.Key.Comma
    raylib_key_map[rl.KeyboardKey.MINUS] = imgui.Key.Minus
    raylib_key_map[rl.KeyboardKey.PERIOD] = imgui.Key.Period
    raylib_key_map[rl.KeyboardKey.SLASH] = imgui.Key.Slash
    raylib_key_map[rl.KeyboardKey.ZERO] = imgui.Key._0
    raylib_key_map[rl.KeyboardKey.ONE] = imgui.Key._1
    raylib_key_map[rl.KeyboardKey.TWO] = imgui.Key._2
    raylib_key_map[rl.KeyboardKey.THREE] = imgui.Key._3
    raylib_key_map[rl.KeyboardKey.FOUR] = imgui.Key._4
    raylib_key_map[rl.KeyboardKey.FIVE] = imgui.Key._5
    raylib_key_map[rl.KeyboardKey.SIX] = imgui.Key._6
    raylib_key_map[rl.KeyboardKey.SEVEN] = imgui.Key._7
    raylib_key_map[rl.KeyboardKey.EIGHT] = imgui.Key._8
    raylib_key_map[rl.KeyboardKey.NINE] = imgui.Key._9
    raylib_key_map[rl.KeyboardKey.SEMICOLON] = imgui.Key.Semicolon
    raylib_key_map[rl.KeyboardKey.EQUAL] = imgui.Key.Equal
    raylib_key_map[rl.KeyboardKey.A] = imgui.Key.A
    raylib_key_map[rl.KeyboardKey.B] = imgui.Key.B
    raylib_key_map[rl.KeyboardKey.C] = imgui.Key.C
    raylib_key_map[rl.KeyboardKey.D] = imgui.Key.D
    raylib_key_map[rl.KeyboardKey.E] = imgui.Key.E
    raylib_key_map[rl.KeyboardKey.F] = imgui.Key.F
    raylib_key_map[rl.KeyboardKey.G] = imgui.Key.G
    raylib_key_map[rl.KeyboardKey.H] = imgui.Key.H
    raylib_key_map[rl.KeyboardKey.I] = imgui.Key.I
    raylib_key_map[rl.KeyboardKey.J] = imgui.Key.J
    raylib_key_map[rl.KeyboardKey.K] = imgui.Key.K
    raylib_key_map[rl.KeyboardKey.L] = imgui.Key.L
    raylib_key_map[rl.KeyboardKey.M] = imgui.Key.M
    raylib_key_map[rl.KeyboardKey.N] = imgui.Key.N
    raylib_key_map[rl.KeyboardKey.O] = imgui.Key.O
    raylib_key_map[rl.KeyboardKey.P] = imgui.Key.P
    raylib_key_map[rl.KeyboardKey.Q] = imgui.Key.Q
    raylib_key_map[rl.KeyboardKey.R] = imgui.Key.R
    raylib_key_map[rl.KeyboardKey.S] = imgui.Key.S
    raylib_key_map[rl.KeyboardKey.T] = imgui.Key.T
    raylib_key_map[rl.KeyboardKey.U] = imgui.Key.U
    raylib_key_map[rl.KeyboardKey.V] = imgui.Key.V
    raylib_key_map[rl.KeyboardKey.W] = imgui.Key.W
    raylib_key_map[rl.KeyboardKey.X] = imgui.Key.X
    raylib_key_map[rl.KeyboardKey.Y] = imgui.Key.Y
    raylib_key_map[rl.KeyboardKey.Z] = imgui.Key.Z
    raylib_key_map[rl.KeyboardKey.SPACE] = imgui.Key.Space
    raylib_key_map[rl.KeyboardKey.ESCAPE] = imgui.Key.Escape
    raylib_key_map[rl.KeyboardKey.ENTER] = imgui.Key.Enter
    raylib_key_map[rl.KeyboardKey.TAB] = imgui.Key.Tab
    raylib_key_map[rl.KeyboardKey.BACKSPACE] = imgui.Key.Backspace
    raylib_key_map[rl.KeyboardKey.INSERT] = imgui.Key.Insert
    raylib_key_map[rl.KeyboardKey.DELETE] = imgui.Key.Delete
    raylib_key_map[rl.KeyboardKey.RIGHT] = imgui.Key.RightArrow
    raylib_key_map[rl.KeyboardKey.LEFT] = imgui.Key.LeftArrow
    raylib_key_map[rl.KeyboardKey.DOWN] = imgui.Key.DownArrow
    raylib_key_map[rl.KeyboardKey.UP] = imgui.Key.UpArrow
    raylib_key_map[rl.KeyboardKey.PAGE_UP] = imgui.Key.PageUp
    raylib_key_map[rl.KeyboardKey.PAGE_DOWN] = imgui.Key.PageDown
    raylib_key_map[rl.KeyboardKey.HOME] = imgui.Key.Home
    raylib_key_map[rl.KeyboardKey.END] = imgui.Key.End
    raylib_key_map[rl.KeyboardKey.CAPS_LOCK] = imgui.Key.CapsLock
    raylib_key_map[rl.KeyboardKey.SCROLL_LOCK] = imgui.Key.ScrollLock
    raylib_key_map[rl.KeyboardKey.NUM_LOCK] = imgui.Key.NumLock
    raylib_key_map[rl.KeyboardKey.PRINT_SCREEN] = imgui.Key.PrintScreen
    raylib_key_map[rl.KeyboardKey.PAUSE] = imgui.Key.Pause
    raylib_key_map[rl.KeyboardKey.F1] = imgui.Key.F1
    raylib_key_map[rl.KeyboardKey.F2] = imgui.Key.F2
    raylib_key_map[rl.KeyboardKey.F3] = imgui.Key.F3
    raylib_key_map[rl.KeyboardKey.F4] = imgui.Key.F4
    raylib_key_map[rl.KeyboardKey.F5] = imgui.Key.F5
    raylib_key_map[rl.KeyboardKey.F6] = imgui.Key.F6
    raylib_key_map[rl.KeyboardKey.F7] = imgui.Key.F7
    raylib_key_map[rl.KeyboardKey.F8] = imgui.Key.F8
    raylib_key_map[rl.KeyboardKey.F9] = imgui.Key.F9
    raylib_key_map[rl.KeyboardKey.F10] = imgui.Key.F10
    raylib_key_map[rl.KeyboardKey.F11] = imgui.Key.F11
    raylib_key_map[rl.KeyboardKey.F12] = imgui.Key.F12
    raylib_key_map[rl.KeyboardKey.LEFT_SHIFT] = imgui.Key.LeftShift
    raylib_key_map[rl.KeyboardKey.LEFT_CONTROL] = imgui.Key.LeftCtrl
    raylib_key_map[rl.KeyboardKey.LEFT_ALT] = imgui.Key.LeftAlt
    raylib_key_map[rl.KeyboardKey.LEFT_SUPER] = imgui.Key.LeftSuper
    raylib_key_map[rl.KeyboardKey.RIGHT_SHIFT] = imgui.Key.RightShift
    raylib_key_map[rl.KeyboardKey.RIGHT_CONTROL] = imgui.Key.RightCtrl
    raylib_key_map[rl.KeyboardKey.RIGHT_ALT] = imgui.Key.RightAlt
    raylib_key_map[rl.KeyboardKey.RIGHT_SUPER] = imgui.Key.RightSuper
    raylib_key_map[rl.KeyboardKey.KB_MENU] = imgui.Key.Menu
    raylib_key_map[rl.KeyboardKey.LEFT_BRACKET] = imgui.Key.LeftBracket
    raylib_key_map[rl.KeyboardKey.BACKSLASH] = imgui.Key.Backslash
    raylib_key_map[rl.KeyboardKey.RIGHT_BRACKET] = imgui.Key.RightBracket
    raylib_key_map[rl.KeyboardKey.GRAVE] = imgui.Key.GraveAccent
    raylib_key_map[rl.KeyboardKey.KP_0] = imgui.Key.Keypad0
    raylib_key_map[rl.KeyboardKey.KP_1] = imgui.Key.Keypad1
    raylib_key_map[rl.KeyboardKey.KP_2] = imgui.Key.Keypad2
    raylib_key_map[rl.KeyboardKey.KP_3] = imgui.Key.Keypad3
    raylib_key_map[rl.KeyboardKey.KP_4] = imgui.Key.Keypad4
    raylib_key_map[rl.KeyboardKey.KP_5] = imgui.Key.Keypad5
    raylib_key_map[rl.KeyboardKey.KP_6] = imgui.Key.Keypad6
    raylib_key_map[rl.KeyboardKey.KP_7] = imgui.Key.Keypad7
    raylib_key_map[rl.KeyboardKey.KP_8] = imgui.Key.Keypad8
    raylib_key_map[rl.KeyboardKey.KP_9] = imgui.Key.Keypad9
    raylib_key_map[rl.KeyboardKey.KP_DECIMAL] = imgui.Key.KeypadDecimal
    raylib_key_map[rl.KeyboardKey.KP_DIVIDE] = imgui.Key.KeypadDivide
    raylib_key_map[rl.KeyboardKey.KP_MULTIPLY] = imgui.Key.KeypadMultiply
    raylib_key_map[rl.KeyboardKey.KP_SUBTRACT] = imgui.Key.KeypadSubtract
    raylib_key_map[rl.KeyboardKey.KP_ADD] = imgui.Key.KeypadAdd
    raylib_key_map[rl.KeyboardKey.KP_ENTER] = imgui.Key.KeypadEnter
    raylib_key_map[rl.KeyboardKey.KP_EQUAL] = imgui.Key.KeypadEqual
}

@private
setup_mouse_cursor :: proc() {
    mouse_cursor_map[imgui.MouseCursor.Arrow] = rl.MouseCursor.ARROW;
    mouse_cursor_map[imgui.MouseCursor.TextInput] = rl.MouseCursor.IBEAM;
    mouse_cursor_map[imgui.MouseCursor.Hand] = rl.MouseCursor.POINTING_HAND;
    mouse_cursor_map[imgui.MouseCursor.ResizeAll] = rl.MouseCursor.RESIZE_ALL;
    mouse_cursor_map[imgui.MouseCursor.ResizeEW] = rl.MouseCursor.RESIZE_EW;
    mouse_cursor_map[imgui.MouseCursor.ResizeNESW] = rl.MouseCursor.RESIZE_NESW;
    mouse_cursor_map[imgui.MouseCursor.ResizeNS] = rl.MouseCursor.RESIZE_NS;
    mouse_cursor_map[imgui.MouseCursor.ResizeNWSE] = rl.MouseCursor.RESIZE_NWSE;
    mouse_cursor_map[imgui.MouseCursor.NotAllowed] = rl.MouseCursor.NOT_ALLOWED;
}

@private
setup_backend :: proc() {
    io: ^imgui.IO = imgui.GetIO()
    io.BackendPlatformName = "imgui_impl_raylib"

    io.BackendFlags |= { imgui.BackendFlag.HasMouseCursors }

    io.MousePos = { 0, 0 }

    io.SetClipboardTextFn = set_clip_text_callback
    io.GetClipboardTextFn = get_clip_text_callback

    io.ClipboardUserData = nil
}

@private
set_clip_text_callback :: proc "c" (user_data: rawptr, text: cstring) {
    rl.SetClipboardText(text)
}

@private
get_clip_text_callback :: proc "c" (user_data: rawptr) -> cstring {
    return rl.GetClipboardText()
}