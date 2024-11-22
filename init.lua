leclaireur={}
local S = airutils.S

function leclaireur.register_parts_method(self)
    local pos = self.object:get_pos()

    --minetest.chat_send_all(self.initial_properties.textures[19])
    --airutils.paint(self.wheels:get_luaentity(), self._color)
end

function leclaireur.destroy_parts_method(self)
    local pos = self.object:get_pos()
    if not minetest.settings:get_bool('leclaireur.disable_craftitems') then
        pos.y=pos.y+2

        for i=1,2 do
	        minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:tin_ingot')
        end

        for i=1,6 do
	        minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:mese_crystal')
            minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:diamond')
        end
    else
        minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'leclaireur:leclaireur')
    end
end

function leclaireur.step_additional_function(self)
    if self.isonground and self._engine_running == false then
        --minetest.chat_send_all("no chão")
        self.object:set_animation({x = 40, y = 40}, 0, 0, false)
    else
        --minetest.chat_send_all("voando")
        self.object:set_animation({x = 1, y = 1}, 0, 0, false)
    end

    self._flap = 0 --hack to avoid wing reconfiguration
    self._lift = 10
    self._wing_configuration = self._wing_angle_of_attack
    if self._engine_running == false then
        self._last_accel.y = airutils.gravity
    end
    if self._engine_running and self._longit_speed ~= nil then
        if self._longit_speed > 12 then
            self._lift = 3.5
            self._wing_configuration = 0.1
        end
    end

    if (self.driver_name==nil) and (self.co_pilot==nil) then --pilot or copilot
        return
    end

    local pos = self._curr_pos

    local climb_angle = airutils.get_gauge_angle(self._climb_rate)
    self.object:set_bone_position("climber", {x=-1.98,y=2.40,z=10.2}, {x=0,y=0,z=climb_angle-90})

    local speed_angle = airutils.get_gauge_angle(self._indicated_speed, -45)
    self.object:set_bone_position("speed", {x=-7.01,y=1.26,z=10.2}, {x=0,y=0,z=speed_angle})

    local energy_indicator_angle = airutils.get_gauge_angle((self._max_fuel - self._energy)/1.5) - 90
    self.object:set_bone_position("fuel", {x=0, y=0, z=10.2}, {x=0, y=0, z=-energy_indicator_angle+180})

    self.object:set_bone_position("compass", {x=0, y=2.8, z=10.3}, {x=0, y=0, z=-(math.deg(self._yaw))})
    self.object:set_bone_position("compass_plan", {x=0, y=2.8, z=10.25}, {x=0, y=0, z=airutils.get_adf_angle(self, pos)})

    --altimeter
    local altitude = (pos.y / 0.32) / 100
    local hour, minutes = math.modf( altitude )
    hour = math.fmod (hour, 10)
    minutes = minutes * 100
    minutes = (minutes * 100) / 100
    local minute_angle = (minutes*-360)/100
    local hour_angle = (hour*-360)/10 + ((minute_angle*36)/360)
    self.object:set_bone_position("altimeter_pt_1", {x=-4.63, y=2.4, z=10.2}, {x=0, y=0, z=(hour_angle)})
    self.object:set_bone_position("altimeter_pt_2", {x=-4.63, y=2.4, z=10.2}, {x=0, y=0, z=(minute_angle)})

    --adjust power indicator
    local power_indicator_angle = airutils.get_gauge_angle(self._power_lever/6.5)
    self.object:set_bone_position("power", {x=2.8,y=2.40,z=10.2}, {x=0,y=0,z=power_indicator_angle - 90})

    --set stick position
    local stick_z = 9 + (self._elevator_angle / self._elevator_limit )
    self.object:set_bone_position("stick.l", {x=-4.25, y=0.5, z=stick_z}, {x=0,y=0,z=self._rudder_angle})
    self.object:set_bone_position("stick.r", {x=4.25, y=0.5, z=stick_z}, {x=0,y=0,z=self._rudder_angle})
end

local function ground_pitch(self, longit_speed, curr_pitch)
    local newpitch = curr_pitch
    if self._last_longit_speed == nil then self._last_longit_speed = 0 end

    -- Estado atual do sistema
    if self._current_value == nil then self._current_value = 0 end -- Valor atual do sistema
    if self._last_error == nil then self._last_error = 0 end -- Último erro registrado

    -- adjust pitch at ground
    if math.abs(longit_speed) < self._tail_lift_max_speed then
        local speed_range = self._tail_lift_max_speed - self._tail_lift_min_speed
        local percentage = 1-((math.abs(longit_speed) - self._tail_lift_min_speed)/speed_range)
        if percentage > 1 then percentage = 1 end
        if percentage < 0 then percentage = 0 end
        local angle = self._tail_angle * percentage
        local rad_angle = math.rad(angle)

        if newpitch < rad_angle then newpitch = rad_angle end --ja aproveita o pitch atual se ja estiver cerrto
        --[[self._current_value = curr_pitch
        local kp = (longit_speed - self._tail_lift_min_speed)/10
        local output, last_error = airutils.pid_controller(self._current_value, rad_angle, self._last_error, self.dtime, kp)
        self._last_error = last_error
        newpitch = output]]--

        if newpitch > math.rad(self._tail_angle) then newpitch = math.rad(self._tail_angle) end --não queremos arrastar o cauda no chão
    end

    return newpitch
end

function leclaireur.logic(self)
    local velocity = self.object:get_velocity()
    local rem_obj = self.object:get_attach()
    local extern_ent = nil
    if rem_obj then
        extern_ent = rem_obj:get_luaentity()
    end
    local curr_pos = self.object:get_pos()
    self._curr_pos = curr_pos --shared
    self._last_accel = self.object:get_acceleration()

    self._last_time_command = self._last_time_command + self.dtime

    if self._last_time_command > 1 then self._last_time_command = 1 end

    local player = nil
    if self.driver_name then player = minetest.get_player_by_name(self.driver_name) end
    local co_pilot = nil
    if self.co_pilot and self._have_copilot then co_pilot = minetest.get_player_by_name(self.co_pilot) end

    --test collision
    airutils.testImpact(self, velocity, curr_pos)

    --if self._autoflymode == true then airutils.seats_update(self) end

    if player then
        local ctrl = player:get_player_control()
        ---------------------
        -- change the driver
        ---------------------
        if co_pilot and self._have_copilot and self._last_time_command >= 1 then
            if self._command_is_given == true then
                if ctrl.sneak or ctrl.jump or ctrl.up or ctrl.down or ctrl.right or ctrl.left then
                    self._last_time_command = 0
                    --take the control
                    airutils.transfer_control(self, false)
                end
            else
                if ctrl.sneak == true and ctrl.jump == true then
                    self._last_time_command = 0
                    --trasnfer the control to student
                    airutils.transfer_control(self, true)
                end
            end
        end
        -----------
        --autopilot
        -----------
        if self._instruction_mode == false and self._last_time_command >= 1 then
            if self._autopilot == true then
                if ctrl.sneak or ctrl.jump or ctrl.up or ctrl.down or ctrl.right or ctrl.left then
                    self._last_time_command = 0
                    self._autopilot = false
                    minetest.chat_send_player(self.driver_name,S(" >>> Autopilot deactivated"))
                end
            else
                if ctrl.sneak == true and ctrl.jump == true and self._have_auto_pilot then
                    self._last_time_command = 0
                    self._autopilot = true
                    self._auto_pilot_altitude = curr_pos.y
                    minetest.chat_send_player(self.driver_name,core.colorize('#00ff00', S(" >>> Autopilot on")))
                end
            end
        end
    end

    if not self.object:get_acceleration() then return end
    local accel_y = self.object:get_acceleration().y
    local rotation = self.object:get_rotation()
    local yaw = rotation.y
	local newyaw=yaw
	local roll = rotation.z
	local newroll=roll
    newroll = math.floor(newroll/360)
    newroll = newroll * 360

    local hull_direction = airutils.rot_to_dir(rotation) --minetest.yaw_to_dir(yaw)
    local nhdir = {x=hull_direction.z,y=0,z=-hull_direction.x}		-- lateral unit vector

    local longit_speed = vector.dot(velocity,hull_direction)

    if extern_ent then
        if extern_ent.curr_speed then longit_speed = extern_ent.curr_speed end
        --minetest.chat_send_all(dump(longit_speed))
    end

    self._longit_speed = longit_speed
    local longit_drag = vector.multiply(hull_direction,longit_speed*
            longit_speed*self._longit_drag_factor*-1*airutils.sign(longit_speed))
	local later_speed = airutils.dot(velocity,nhdir)
    --minetest.chat_send_all('later_speed: '.. later_speed)
	local later_drag = vector.multiply(nhdir,later_speed*later_speed*
            self._later_drag_factor*-1*airutils.sign(later_speed))
    local accel = vector.add(longit_drag,later_drag)
    local stop = false

    local is_flying = true
    if self.colinfo then
        is_flying = (not self.colinfo.touching_ground) and (self.isinliquid == false)
    else
        --special routine for automated plane
        if extern_ent then
            if not extern_ent.on_rightclick then
                local touch_point = (self.initial_properties.collisionbox[2])-0.5
                local node_bellow = airutils.nodeatpos(airutils.pos_shift(curr_pos,{y=touch_point}))
                --minetest.chat_send_all(dump(node_bellow.drawtype))
                if (node_bellow and node_bellow.drawtype ~= 'airlike') then
	                is_flying = false
                end
            end
        end
    end
    --minetest.chat_send_all(dump(is_flying))
    --if is_flying then minetest.chat_send_all('is flying') end

    local is_attached = airutils.checkAttach(self, player)
    if self._indicated_speed == nil then self._indicated_speed = 0 end

    -- for some engine error the player can be detached from the machine, so lets set him attached again
    airutils.checkattachBug(self)


    if self._custom_step_additional_function then
        self._custom_step_additional_function(self)
    end

    --fix old planes
    if not self._flap then self._flap = false end
    if not self._wing_configuration then self._wing_configuration = self._wing_angle_of_attack end


    if self._wing_configuration == self._wing_angle_of_attack and self._flap then
        airutils.flap_on(self)
    end
    if self._wing_configuration ~= self._wing_angle_of_attack and self._flap == false then
        airutils.flap_off(self)
    end

    --landing light
    if self._have_landing_lights then
        airutils.landing_lights_operate(self)
    end

    --smoke and fire
    if self._engine_running then
        local curr_health_percent = (self.hp_max * 100)/self._max_plane_hp
        if curr_health_percent < 20 then
            airutils.add_smoke_trail(self, 2)
        elseif curr_health_percent < 50 then
            airutils.add_smoke_trail(self, 1)
        end
    else
        if self._smoke_spawner and not self._smoke_semaphore then
            self._smoke_semaphore = 1 --to set it only one time
            minetest.after(5, function()
                if self._smoke_spawner then
                    minetest.delete_particlespawner(self._smoke_spawner)
                    self._smoke_spawner = nil
                    self._smoke_semaphore = nil
                end
            end)
        end
    end

    --adjust elevator pitch (3d model)
    self.object:set_bone_position("elevator", self._elevator_pos, {x=-self._elevator_angle*2 - 90, y=0, z=0})
    --adjust rudder
    self.object:set_bone_position("rudder", self._rudder_pos, {x=0,y=self._rudder_angle,z=0})
    --adjust ailerons
    if self._aileron_r_pos and self._aileron_l_pos then
        local ailerons = self._rudder_angle
        if self._invert_ailerons then ailerons = ailerons * -1 end
        self.object:set_bone_position("aileron.r", self._aileron_r_pos, {x=-ailerons - 90,y=0,z=0})
        self.object:set_bone_position("aileron.l", self._aileron_l_pos, {x=ailerons - 90,y=0,z=0})
    end

    if (math.abs(velocity.x) < 0.1 and math.abs(velocity.z) < 0.1) and is_flying == false and is_attached == false and self._engine_running == false then
        if self._ground_friction then
            if not self.isinliquid then self.object:set_velocity({x=0,y=airutils.gravity*self.dtime,z=0}) end
        end
        return
    end

    --adjust climb indicator
    local y_velocity = 0
    if self._engine_running or is_flying then y_velocity = velocity.y end
    local climb_rate =  y_velocity
    if climb_rate > 5 then climb_rate = 5 end
    if climb_rate < -5 then
        climb_rate = -5
    end

    -- pitch
    local newpitch = airutils.get_plane_pitch(y_velocity, longit_speed, self._min_speed, self._angle_of_attack)

    --for airplanes with cannard or pendulum wing
    local actuator_angle = self._elevator_angle
    if self._inverted_pitch_reaction then actuator_angle = -1*self._elevator_angle end

    --ajustar angulo de ataque
    if longit_speed > self._min_speed then
        local percentage = math.abs(((longit_speed * 100)/(self._min_speed + 5))/100)
        if percentage > 1.5 then percentage = 1.5 end

        self._angle_of_attack = self._wing_angle_of_attack - ((actuator_angle / self._elevator_response_attenuation)*percentage)

        --airutils.adjust_attack_angle_by_speed(angle_of_attack, min_angle, max_angle, limit, longit_speed, ideal_step, dtime)
        self._angle_of_attack = airutils.adjust_attack_angle_by_speed(self._angle_of_attack, self._min_attack_angle, self._max_attack_angle, 40, longit_speed, airutils.ideal_step, self.dtime)

        if self._angle_of_attack < self._min_attack_angle then
            self._angle_of_attack = self._min_attack_angle
            actuator_angle = actuator_angle - 0.2
        end --limiting the negative angle]]--
        --[[if self._angle_of_attack > self._max_attack_angle then
            self._angle_of_attack = self._max_attack_angle
            actuator_angle = actuator_angle + 0.2
        end --limiting the very high climb angle due to strange behavior]]--]]--

        if self._inverted_pitch_reaction then self._elevator_angle = -1*actuator_angle end --revert the reversion

    end


    --minetest.chat_send_all(self._angle_of_attack)

    -- adjust pitch at ground
    if math.abs(longit_speed) > self._tail_lift_min_speed and is_flying == false then
        newpitch = ground_pitch(self, longit_speed, newpitch)
    else
        if math.abs(longit_speed) < self._tail_lift_min_speed then
            newpitch = math.rad(self._tail_angle)
        end
    end

    -- new yaw
	if math.abs(self._rudder_angle)>1.5 then
        local turn_rate = math.rad(self._yaw_turn_rate)
        local yaw_turn = self.dtime * math.rad(self._rudder_angle) * turn_rate *
                airutils.sign(longit_speed) * math.abs(longit_speed/2)
		newyaw = yaw + yaw_turn
	end

    --roll adjust
    ---------------------------------
    local delta = 0.002
    if is_flying then
        local roll_reference = newyaw
        local sdir = minetest.yaw_to_dir(roll_reference)
        local snormal = {x=sdir.z,y=0,z=-sdir.x}	-- rightside, dot is negative
        local prsr = airutils.dot(snormal,nhdir)
        local rollfactor = -90
        local roll_rate = math.rad(10)
        newroll = (prsr*math.rad(rollfactor)) * (later_speed * roll_rate) * airutils.sign(longit_speed)

        --[[local rollRotation = -self._rudder_angle * 0.1
        newroll = rollRotation]]--

        --minetest.chat_send_all('newroll: '.. newroll)
    else
        delta = 0.2
        if roll > 0 then
            newroll = roll - delta
            if newroll < 0 then newroll = 0 end
        end
        if roll < 0 then
            newroll = roll + delta
            if newroll > 0 then newroll = 0 end
        end
    end

    ---------------------------------
    -- end roll

    local pilot = player
    if self._have_copilot then
        if self._command_is_given and co_pilot then
            pilot = co_pilot
        else
            self._command_is_given = false
        end
    end

    ------------------------------------------------------
    --accell calculation block
    ------------------------------------------------------
    if is_attached or co_pilot then
        if self._autopilot ~= true then
            accel, stop = airutils.control(self, self.dtime, hull_direction,
                longit_speed, longit_drag, later_speed, later_drag, accel, pilot, is_flying)
        else
            accel = airutils.autopilot(self, self.dtime, hull_direction, longit_speed, accel, curr_pos)
        end
    end
    --end accell

    --get disconnected players
    if self._autoflymode ~= true then
        airutils.rescueConnectionFailedPassengers(self)
    end

    if accel == nil then accel = {x=0,y=0,z=0} end

    --lift calculation
    accel.y = accel_y

    --lets apply some bob in water
	if self.isinliquid then
        local bob = airutils.minmax(airutils.dot(accel,hull_direction),0.02)	-- vertical bobbing
        if bob < 0 then bob = 0 end
        accel.y = accel.y + bob
        local max_pitch = 6
        local ref_speed = longit_speed * 20
        if ref_speed < 0 then ref_speed = 0 end
        local h_vel_compensation = ((ref_speed * 100)/max_pitch)/100
        if h_vel_compensation < 0 then h_vel_compensation = 0 end
        if h_vel_compensation > max_pitch then h_vel_compensation = max_pitch end
        --minetest.chat_send_all(h_vel_compensation)
        newpitch = newpitch + (velocity.y * math.rad(max_pitch - h_vel_compensation))

        if airutils.use_water_particles == true and airutils.add_splash and self._splash_x_position and self.buoyancy then
            local splash_frequency = 0.15
            if self._last_splash == nil then self._last_splash = 0.5 else self._last_splash = self._last_splash + self.dtime end
            if longit_speed >= 2.0 and self._last_vel and self._last_splash >= splash_frequency then
                self._last_splash = 0
                local splash_pos = vector.new(curr_pos)
                local bellow_position = self.initial_properties.collisionbox[2]
                local collision_height = self.initial_properties.collisionbox[5] - bellow_position
                splash_pos.y = splash_pos.y + (bellow_position + (collision_height * self.buoyancy)) - (collision_height/10)
                airutils.add_splash(splash_pos, newyaw, self._splash_x_position)
            end
        end
    end

    local new_accel = accel
    self.gravity_last_status_message = self.gravity_last_status_message or 0
    local gravity_status = 0

    local is_stall = longit_speed < (self._min_speed+0.5) and climb_rate < -1.5 and is_flying
    if longit_speed > 12 and not is_stall then
        --[[lets do something interesting:
        here I'll fake the longit speed effect for takeoff, to force the airplane
        to use more runway
        ]]--
        local factorized_longit_speed = longit_speed
        if is_flying == false and airutils.quadBezier then
            local takeoff_speed = self._min_speed * 4  --so first I'll consider the takeoff speed 4x the minimal flight speed
            if longit_speed < takeoff_speed and longit_speed > self._min_speed then -- then if the airplane is above the mininam speed and bellow the take off
                local scale = (longit_speed*1)/takeoff_speed --get a scale of current longit speed relative to takeoff speed
                if scale == nil then scale = 0 end --lets avoid any nil
                factorized_longit_speed = airutils.quadBezier(scale, self._min_speed, longit_speed, longit_speed) --here the magic happens using a bezier curve
                --minetest.chat_send_all("factor: " .. factorized_longit_speed .. " - longit: " .. longit_speed .. " - scale: " .. scale)
                if factorized_longit_speed < 0 then factorized_longit_speed = 0 end --lets avoid negative numbers
                if factorized_longit_speed == nil then factorized_longit_speed = longit_speed end --and nil numbers
            end
        end

        local ceiling = 15000
        new_accel = airutils.getLiftAccel(self, velocity, new_accel, factorized_longit_speed, roll, curr_pos, self._lift, ceiling, self._wing_span)
    else
        --gravity works
        if not self._engine_running then
            new_accel.y = airutils.gravity
            gravity_status = 0
        else
            --antigravity
            gravity_status = 1
            local player = core.get_player_by_name(self.driver_name or "")
            if player then
                leclaireur.control_flight(self, player)
            end

            self._taxing_gravity = self._taxing_gravity or 0
            local y_accel = self._taxing_gravity + (airutils.gravity*-1)
            new_accel.y = y_accel --sets the anti gravity
            leclaireur.gravity_auto_correction(self, self.dtime)
        end
    end
    -- end lift
    if self.gravity_last_status_message ~= gravity_status then
        self.gravity_last_status_message = gravity_status
        if gravity_status == 0 then
            core.chat_send_player(self.driver_name, core.colorize('#ff0000',"Antigravity was turned off"))
        else
            self._taxing_gravity = 100 + (airutils.gravity*-1)
            core.chat_send_player(self.driver_name, core.colorize('#00ff00',"Antigravity was turned on"))
            minetest.sound_play("leclaireur_alert", {
                object = self.object,
                max_hear_distance = 15,
                gain = 1.0,
                fade = 0.0,
                pitch = 1.0,
            })
        end
    end


    --wind effects
    if longit_speed > 1.5 and airutils.wind then
        local wind = airutils.get_wind(curr_pos, 0.1)
        new_accel = vector.add(new_accel, wind)
    end

    if stop ~= true then --maybe == nil
        self._last_accell = new_accel
	    self.object:move_to(curr_pos)
        --airutils.set_acceleration(self.object, new_accel)
        local limit = (self._max_speed/self.dtime)
        if new_accel.y > limit then new_accel.y = limit end --it isn't a rocket :/

    else
        if stop == true then
            self._last_accell = vector.new() --self.object:get_acceleration()
            self.object:set_acceleration({x=0,y=0,z=0})
            self.object:set_velocity({x=0,y=0,z=0})
        end
    end

    if self.wheels then
        if is_flying == false then --isn't flying?
            --animate wheels
            local min_speed_animation = 0.1
            if math.abs(velocity.x) > min_speed_animation or math.abs(velocity.z) > min_speed_animation then
                self.wheels:set_animation_frame_speed(longit_speed * 10)
            else
                if extern_ent then
                    self.wheels:set_animation_frame_speed(longit_speed * 10)
                else
                    self.wheels:set_animation_frame_speed(0)
                end
            end
        else
            --stop wheels
            self.wheels:set_animation_frame_speed(0)
        end
    end

    ------------------------------------------------------
    -- end accell
    ------------------------------------------------------

    ------------------------------------------------------
    -- sound and animation
    ------------------------------------------------------
    airutils.engine_set_sound_and_animation(self)

    ------------------------------------------------------

    --self.object:get_luaentity() --hack way to fix jitter on climb

    --GAUGES
    --minetest.chat_send_all('rate '.. climb_rate)
    local climb_angle = airutils.get_gauge_angle(climb_rate)
    self._climb_rate = climb_rate

    local indicated_speed = longit_speed * 0.9
    if indicated_speed < 0 then indicated_speed = 0 end
    self._indicated_speed = indicated_speed
    local speed_angle = airutils.get_gauge_angle(indicated_speed, -45)

    --adjust power indicator
    local power_indicator_angle = airutils.get_gauge_angle(self._power_lever/10) + 90
    local fuel_in_percent = (self._energy * 1)/self._max_fuel
    local energy_indicator_angle = (180*fuel_in_percent)-180    --(airutils.get_gauge_angle((self._max_fuel - self._energy)*2)) - 90

    if is_attached then
        if self._show_hud then
            airutils.update_hud(player, climb_angle, speed_angle, power_indicator_angle, energy_indicator_angle)
        else
            airutils.remove_hud(player)
        end
    end

    if is_flying == false then
        -- new yaw
        local turn_rate = math.rad(30)
        local yaw_turn = self.dtime * math.rad(self._rudder_angle) * turn_rate *
                    airutils.sign(longit_speed) * math.abs(longit_speed/2)
	    newyaw = yaw + yaw_turn
    end

    if player and self._use_camera_relocation then
        --minetest.chat_send_all(dump(newroll))
        local new_eye_offset = airutils.camera_reposition(player, newpitch, newroll)
        player:set_eye_offset(new_eye_offset, {x = 0, y = 1, z = -30})
    end

    --apply rotations
    self.object:set_rotation({x=newpitch,y=newyaw,z=newroll})
    --end

    if (longit_speed / 2) > self._max_speed and self._flap == true then
        if is_attached and self.driver_name then
            minetest.chat_send_player(self.driver_name, core.colorize('#ff0000', S(" >>> Flaps retracted due for overspeed")))
        end
        self._flap = false
    end

    -- calculate energy consumption --
    airutils.consumptionCalc(self, accel)

    --saves last velocity for collision detection (abrupt stop)
    self._last_accel = new_accel
    self._last_vel = self.object:get_velocity()
    self._last_longit_speed = longit_speed
    self._yaw = newyaw
    self._roll = newroll
    self._pitch = newpitch
end

leclaireur.plane_properties = {
	initial_properties = {
	    physical = true,
        collide_with_objects = true,
	    collisionbox = {-3, -3.45, -3, 3, 1, 3},
	    selectionbox = {-2, -3, -2, 2, 1.2, 2},
	    visual = "mesh",
        backface_culling = true,
	    mesh = "leclaireur.b3d",
        stepheight = 0.5,
        textures = {
            "airutils_black.png", --entrada motor
            "airutils_black.png", --interior caixa trem de pouso
            "leclaireur_canopie.png", --canopie
            "airutils_aluminum.png", --suportes motores
            "airutils_black.png", --motores
            "leclaireur_painting.png", --det motores
            "leclaireur_painting.png", --quilhas
            "airutils_metal.png", --lasers
            "leclaireur_painting.png", --carenagem lasers
            "leclaireur_painting.png", --portas trem
            "airutils_black.png", --entrada nariz
            "leclaireur_panel.png", --painel
            "airutils_metal.png", --entrada nariz (grades)
            "airutils_black.png", --exaustores motores
            "airutils_metal.png", --trem de aterragem
            "airutils_grey.png", --trem de aterragem pt 2
            "leclaireur_seats.png", --bancos
            "airutils_black.png", --interior
            "leclaireur_painting.png", --fuselagem
            "leclaireur_painting.png", --asas
            },
    },
    textures = {},
    _anim_frames = 40,
	driver_name = nil,
	sound_handle = nil,
    owner = "",
    static_save = true,
    infotext = "",
    hp_max = 50,
    shaded = true,
    show_on_minimap = true,
    springiness = 0.1,
    buoyancy = 1.02,
    physics = airutils.physics,
    _no_propeller = true,
    _custom_step_additional_function = leclaireur.step_additional_function,
    _vehicle_name = "l'Eclaireur",
    _seats = {{x=-5.28,y=-8,z=-5.63},{x=5.28,y=-8,z=-5.63},},
    _seats_rot = {0, 0,},  --necessary when using reversed seats
    _have_copilot = true, --wil use the second position of the _seats list
    _have_landing_lights = true,
    _have_auto_pilot = true,
    _have_adf = true,
    _max_plane_hp = 50,
    _enable_fire_explosion = false,
    _longit_drag_factor = 0.13*0.13,
    _later_drag_factor = 2.0,
    _wing_angle_of_attack = 2.5,
    _wing_angle_extra_flaps = 0,
    _wing_span = 12, --meters
    _min_speed = 4,
    _max_speed = 20,
    _max_fuel = 100,
    _speed_not_exceed = 100,
    _damage_by_wind_speed = 2,
    _hard_damage = false,
    _min_attack_angle = -90,
    _max_attack_angle = 90,
    _elevator_auto_estabilize = 100,
    _tail_lift_min_speed = 0,
    _tail_lift_max_speed = 0,
    _max_engine_acc = 12.0,
    _tail_angle = 0,
    _lift = 10,
    _trunk_slots = 16, --the trunk slots
    _rudder_limit = 40.0,
    _elevator_limit = 15.0,
    _flap_limit = 10.0, --just a decorarion, in degrees
    _elevator_response_attenuation = 4,
    _pitch_intensity = 0.1,
    _yaw_intensity = 10,
    _yaw_turn_rate = 10, --degrees
    _elevator_pos = {x=0, y=2.5, z=-45},
    _rudder_pos = {x=0,y=0,z=0},
    _aileron_r_pos = {x=0,y=0,z=0},
    _aileron_l_pos = {x=0,y=0,z=0},
    _color = "#FFFFFF",
    _color_2 = "#FFFFFF",
    _rudder_angle = 0,
    _acceleration = 0,
    _engine_running = false,
    _angle_of_attack = 0,
    _elevator_angle = 0,
    _power_lever = 0,
    _last_applied_power = 0,
    _energy = 1.0,
    _last_vel = {x=0,y=0,z=0},
    _longit_speed = 0,
    _show_hud = false,
    _instruction_mode = false, --flag to intruction mode
    _command_is_given = false, --flag to mark the "owner" of the commands now
    _autopilot = false,
    _auto_pilot_altitude = 0,
    _last_accell = {x=0,y=0,z=0},
    _last_time_command = 1,
    _inv = nil,
    _inv_id = "",
    _collision_sound = "airutils_collision", --the col sound
    _engine_sound = "default_furnace_active",
    _painting_texture = {"leclaireur_painting.png",}, --the texture to paint
    _painting_texture_2 = {"airutils_painting_2.png",}, --the texture to paint
    _mask_painting_associations = {},
    _register_parts_method = leclaireur.register_parts_method, --the method to register plane parts
    _destroy_parts_method = leclaireur.destroy_parts_method,
    _plane_y_offset_for_bullet = 1,
    _name_color = 0,
    _name_hor_aligment = 3.0,
    --_custom_punch_when_attached = ww1_planes_lib._custom_punch_when_attached, --the method to execute click action inside the plane
    _custom_pilot_formspec = airutils.pilot_formspec,
    --_custom_pilot_formspec = leclaireur.pilot_formspec,
    _custom_step_additional_function = leclaireur.step_additional_function,

    get_staticdata = airutils.get_staticdata,
    on_deactivate = airutils.on_deactivate,
    on_activate = airutils.on_activate,
    logic = leclaireur.logic,
    on_step = airutils.on_step,
    on_punch = airutils.on_punch,
    on_rightclick = airutils.on_rightclick,
}

dofile(minetest.get_modpath("leclaireur") .. DIR_DELIM .. "crafts.lua")
dofile(minetest.get_modpath("leclaireur") .. DIR_DELIM .. "entities.lua")

--
-- items
--

local old_entities = {"leclaireur:seat_base","leclaireur:engine"}
for _,entity_name in ipairs(old_entities) do
    minetest.register_entity(":"..entity_name, {
        on_activate = function(self, staticdata)
            self.object:remove()
        end,
    })
end

