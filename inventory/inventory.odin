package inventory

import "items"

g_hotbar : [10]Stack
g_hb_index : int = 0

setup_hotbar :: proc() {
	g_hotbar[0] = Stack {
		id = .ROCK,
		count = 1
	}
}

Stack :: struct {
	id: items.Item_Id,
	count: int
}
