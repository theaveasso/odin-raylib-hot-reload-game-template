package game

import "core:encoding/json"
import "core:fmt"
import "core:os"

import rl "vendor:raylib"

Tile :: struct {
	pos, src: rl.Vector2,
	f:        u8,
}

LDtk_Level :: struct {
	identifier:     string,
	layerInstances: []LDtk_Layer_Instance,
}

LDtk_Layer_Instance :: struct {
	__identifier:    string,
	__type:          string,
	__cWid, __cHei:  int,
	intGridCsv:      []int,
	autoLayerTiles:  []LDtk_Auto_Layer_Tile,
	entityInstances: []LDtk_Entity,
	gridTiles:       []LDtk_Grid_Tile,
}

LDtk_Auto_Layer_Tile :: struct {
	px: rl.Vector2,
}

LDtk_Entity :: struct {
	__identifier:       string,
	__worldX, __worldY: f32,
}

LDtk_Grid_Tile :: struct {
	px: rl.Vector2,
}

LDtk_Data :: struct {
	levels: []LDtk_Level,
}

parse_level :: proc() {
	level_data, level_data_ok := os.read_entire_file("res/levels.ldtk")
	assert(level_data_ok, "Failed to read level data")
	defer delete(level_data)

	ldtk_data := new(LDtk_Data)
	defer free(ldtk_data)
	err := json.unmarshal(level_data, ldtk_data, allocator = context.temp_allocator)
	if err != nil {
		fmt.println("Failed to unmarshal level data", err)
		assert(true, "Failed to unmarshal level data")
	}

	for level in ldtk_data.levels {
		if level.identifier != "Level_0" do continue

		for layer in level.layerInstances {
			switch layer.__identifier {

			}
		}
	}
}
