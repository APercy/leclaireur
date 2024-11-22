
if not minetest.settings:get_bool('leclaireur.disable_craftitems') then

end

-- leclaireur
minetest.register_craftitem("leclaireur:leclaireur", {
	description = "l'Eclaireur",
	inventory_image = "leclaireur_icon.png",
    liquids_pointable = true,

	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return
		end

        local pointed_pos = pointed_thing.under
        --local node_below = minetest.get_node(pointed_pos).name
        --local nodedef = minetest.registered_nodes[node_below]

		pointed_pos.y=pointed_pos.y+4.0
		local leclaireur_ent = minetest.add_entity(pointed_pos, "leclaireur:leclaireur")
		if leclaireur_ent and placer then
            local ent = leclaireur_ent:get_luaentity()
            if ent then
                local owner = placer:get_player_name()
                ent.owner = owner
			    leclaireur_ent:set_yaw(placer:get_look_horizontal())
			    itemstack:take_item()
                airutils.create_inventory(ent, ent._trunk_slots, owner)
            end
		end

		return itemstack
	end,
})

--
-- crafting
--

if not minetest.settings:get_bool('leclaireur.disable_craftitems') and minetest.get_modpath("default") then

end

