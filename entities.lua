
--
-- entity
--

leclaireur.vector_up = vector.new(0, 1, 0)

minetest.register_entity('leclaireur:leclaireur',
    airutils.properties_copy(leclaireur.plane_properties)
)

function leclaireur.gravity_auto_correction(self, dtime)
    local factor = 1
    local target_anti_gravity = 0
    self._taxing_gravity = self._taxing_gravity or target_anti_gravity
    --minetest.chat_send_player(self.driver_name, "antes: " .. self._taxing_gravity)
    if self._taxing_gravity > target_anti_gravity then factor = -1 end
    local time_correction = (dtime/airutils.ideal_step)
    local intensity = 2
    local correction = (intensity*factor) * time_correction
    if math.abs(correction) > 1 then correction = 1 * math.sign(correction) end
    --minetest.chat_send_player(self.driver_name, correction)
    local before_correction = self._taxing_gravity
    local new_taxing_gravity = self._taxing_gravity + correction
    if math.sign(before_correction) ~= math.sign(new_taxing_gravity) then
        self._taxing_gravity = target_anti_gravity
    else
        self._taxing_gravity = new_taxing_gravity
    end

end

function leclaireur.control_flight(self, player)
    local ctrl = player:get_player_control()
    local max = 6
    local min = -6
    if ctrl.down then
        if self._taxing_gravity < max then
            self._taxing_gravity = self._taxing_gravity + 1
        end
    elseif ctrl.up then
        if self._taxing_gravity > min then
            self._taxing_gravity = self._taxing_gravity - 1
            if self.isonground then
                self._power_lever = 0
                --self.gravity_status = 0
                self._last_vel = {x=0,y=0,z=0}
                self.object:set_acceleration({x=0,y=0,z=0})
                self.object:set_velocity({x=0,y=0,z=0})
            end
        end
    end
end


