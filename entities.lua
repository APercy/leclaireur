
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

function leclaireur.control(self, dtime, hull_direction, longit_speed, longit_drag,
                            later_speed, later_drag, accel, player, is_flying)
    --if self.driver_name == nil then return end
    local retval_accel = accel

    local stop = false
    local ctrl = nil

	-- player control
	if player then
		ctrl = player:get_player_control()

        if ctrl.aux1 and self._last_time_command > 0.5 then
            self._last_time_command = 0

        end
        ----------------------------------
        -- flap operation
        ----------------------------------
        if ctrl.aux1 and ctrl.sneak and self._last_time_command >= 0.3 and self._wing_angle_extra_flaps then
            self._last_time_command = 0
            airutils.flap_operate(self, player)
        end

        self._acceleration = 0
        if self._engine_running then
            --engine acceleration calc
            local engineacc = (self._power_lever * self._max_engine_acc) / 100;

            local factor = 1

            --increase power lever
            if ctrl.jump then
                airutils.powerAdjust(self, dtime, factor, 1)
            end
            --decrease power lever
            if ctrl.sneak then
                airutils.powerAdjust(self, dtime, factor, -1)
                if self.gravity_status == 0 then
                    if self._power_lever <= 0 and is_flying == false then
                        --break
                        if longit_speed > 0 then
                            engineacc = -1
                            if (longit_speed + engineacc) < 0 then
                                engineacc = longit_speed * -1
                            end
                        end
                        if longit_speed < 0 then
                            engineacc = 1
                            if (longit_speed + engineacc) > 0 then
                                engineacc = longit_speed * -1
                            end
                        end
                        if math.abs(longit_speed) < 0.2 then
                            stop = true
                        end
                    end
                else
	                if longit_speed <= 6.0 and longit_speed > -1.0 then
                        engineacc = -2
	                end
                end
            end
            --do not exceed
            local max_speed = self._max_speed
            if longit_speed > max_speed then
                engineacc = engineacc - (longit_speed-max_speed)
                if engineacc < 0 then engineacc = 0 end
            end
            self._acceleration = engineacc
        else
	        local paddleacc = 0
	        if longit_speed < 1.0 then
                if ctrl.jump then paddleacc = 0.5 end
            end
	        if longit_speed > -1.0 then
                if ctrl.sneak then paddleacc = -0.5 end
	        end
	        self._acceleration = paddleacc
        end

        local hull_acc = vector.multiply(hull_direction,self._acceleration)
        retval_accel=vector.add(retval_accel,hull_acc)

        --pitch
        local pitch_cmd = 0
        if self._yaw_by_mouse == true then
            airutils.set_pitch_by_mouse(self, player)
        else
            if ctrl.up then pitch_cmd = 1 elseif ctrl.down then pitch_cmd = -1 end
            airutils.set_pitch(self, pitch_cmd, dtime)
        end

		-- yaw
        local yaw_cmd = 0
        if self._yaw_by_mouse == true then
	        local rot_y = math.deg(player:get_look_horizontal())
            airutils.set_yaw_by_mouse(self, rot_y)
        else
            if ctrl.right then yaw_cmd = 1 elseif ctrl.left then yaw_cmd = -1 end
            airutils.set_yaw(self, yaw_cmd, dtime)
        end

        --I'm desperate, center all!
        if ctrl.right and ctrl.left then
            self._elevator_angle = 0
            self._rudder_angle = 0
        end

        if ctrl.up and ctrl.down and self._last_time_command > 0.5 then
            self._last_time_command = 0
            local name = player:get_player_name()
            if self._yaw_by_mouse == true then
                minetest.chat_send_player(name, core.colorize('#0000ff', S(" >>> Mouse control disabled.")))
                self._yaw_by_mouse = false
            else
                minetest.chat_send_player(name, core.colorize('#0000ff', S(" >>> Mouse control enabled.")))
                self._yaw_by_mouse = true
            end
        end
	end

    if longit_speed > 0 then
        if ctrl then
            if not (ctrl.right or ctrl.left) then
                airutils.rudder_auto_correction(self, longit_speed, dtime)
            end
        else
            airutils.rudder_auto_correction(self, longit_speed, dtime)
        end
        if airutils.elevator_auto_correction then
            self._elevator_angle = airutils.elevator_auto_correction(self, longit_speed, self.dtime, self._max_speed, self._elevator_angle, self._elevator_limit, airutils.ideal_step, 100)
        end
    end

    return retval_accel, stop
end
