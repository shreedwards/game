package inventory

import "items"

// One item per hotbar slot; an empty slot holds .NOTHING (the enum's zero value,
// so a fresh hotbar starts empty).
g_hotbar : [10]items.Item_Id
g_hb_index : int = 0

setup_hotbar :: proc() {
	g_hotbar[0] = .ROCK
}

// Selects hotbar slot `slot` as the held item, ignoring out-of-range indices so
// callers can pass a raw key offset without bounds-checking.
select_slot :: proc(slot: int) {
	if slot >= 0 && slot < len(g_hotbar) {
		g_hb_index = slot
	}
}

// Puts `id` into the first empty hotbar slot. If the hotbar is full the item is
// dropped (there is no overflow storage yet).
add_to_hotbar :: proc(id: items.Item_Id) {
	for &slot in g_hotbar {
		if slot == .NOTHING {
			slot = id
			return
		}
	}
}
