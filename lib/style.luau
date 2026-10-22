-- Installed as a global sheet so every window draws the same active-block
-- outline; the accent token follows the user's current light or dark theme.
local M = {}

M.activeBlock = [[
.tn-stage .tn-pane.multi:is(.on, .was):not(.headed) .tn-body::before,
.tn-stage .tn-pane.headed.multi:is(.on, .was) .tn-head::before {
    display: none;
}
.tn-stage .tn-pane:not(.pip)::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: 80;
    border-radius: 12px;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.18s var(--ease);
    box-shadow:
        inset 0 0 0 2px rgb(from var(--accent) r g b/78%),
        inset 0 0 18px -7px rgb(from var(--accent) r g b/55%);
}
.tn-stage .tn-pane.on:not(.pip)::after {
    opacity: 1;
}
html.lay-float .tn-stage .tn-pane:not(.pip)::after,
html.lay-studio .tn-stage .tn-pane:not(.pip)::after {
    inset: 4px;
}
.tn-stage .tn-pane.pip.on::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: 80;
    border-radius: inherit;
    pointer-events: none;
    box-shadow:
        inset 0 0 0 2px rgb(from var(--accent) r g b/78%),
        inset 0 1px 0 var(--glass-hi);
}
]]

return M
