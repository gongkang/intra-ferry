# Ferry Transfer Window Redesign

## Goal

Improve the transfer window so it feels like a compact file-transfer workspace instead of a large empty drop area. The user should be able to browse the peer machine's allowed receive paths, pick a target directory, then drag files or folders anywhere over the window to send them.

## Scope

This redesign only changes the transfer window layout and drag/drop interaction. It does not change the network protocol, receive-path authorization, transfer planning, clipboard sync, or settings fields.

## Layout

Use a Finder-like two-column workspace:

- Window title remains `Ferry 传输`.
- The top summary row shows the peer identity and connection status, such as `目标电脑 · 192.168.214.71:49491`.
- The peer identity in the transfer window is read-only status text, not an input. Peer host and port are edited only in the settings window.
- The right side of the top summary row shows an online/offline status badge and a settings button. Directory refresh does not live here; it belongs in the path bar.
- The main workspace is split into a narrow left rail and a directory browser.
- The left rail lists simple destinations: receive roots, recent targets, and the selected target summary when available.
- The directory browser is the main area and receives most of the window space.
- The bottom status row shows the selected send target, the current transfer summary, and progress.

## Path Bar

The path bar sits above the directory list:

- Left side: an icon button for going to the parent directory.
- Center: editable current remote path field.
- Right side: refresh button.
- After refresh: a `设为目标` button to select the currently displayed directory as the send destination.

The path controls should stay on one row and should not wrap at the default transfer window width.

## Directory Browser

The directory list should be the visual center of the window:

- Directories are clickable and enter that remote directory.
- Files are displayed but disabled as send targets.
- Empty, loading, and error states appear inside the list area, not as loose text above the main workspace.
- The selected target is visually distinct from the currently browsed path when they differ.

## Drag And Drop

Remove the permanent standalone drop zone.

When files or folders are dragged into the transfer window:

- The whole content area switches to a full-window drop overlay.
- The overlay says `松开发送`.
- The overlay shows the target path, such as `发送到 /Users/mengxiang`.
- Dropping anywhere inside the window sends to the selected target.
- If no target is selected, the overlay should indicate that a target must be selected first and dropping should not start a transfer.
- Moving the drag out of the window restores the normal browser view.

## Error Handling

Use existing app state messages, but place them in the redesigned regions:

- Peer unavailable: top summary and list empty state.
- Browse failure: list empty/error state.
- No selected target: bottom status and drag overlay.
- Transfer failure: bottom status row.

## Testing

Verification should cover:

- The window opens at the new size and remains resizable.
- Remote path roots load into the directory browser.
- Parent, refresh, enter-directory, and select-current-target actions still work.
- Dragging a file over the window shows the full-window overlay.
- Dropping with a selected target starts a transfer.
- Dropping without a selected target does not start a transfer and shows a clear message.
