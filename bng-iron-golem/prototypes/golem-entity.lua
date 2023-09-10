local shared = require("shared")
local util = require "data/tf_util/tf_util"

local function gaussian (mean, variance)
  return  math.sqrt(-2 * variance * math.log(math.random())) *
          math.cos(2 * math.pi * math.random()) + mean
end

local sound = data.raw.tile["grass-1"].walking_sound

local golem_flags = {"placeable-off-grid", "not-in-kill-statistics", "not-blueprintable", "player-creation", "placeable-player"}

-- local mining_drone_collision_mask = {"not-colliding-with-itself", "player-layer", "consider-tile-transitions"}
local golem_collision_mask = shared.golem_collision_mask

local shuffle = function(n, v)
  --log("Shuffling: "..n..v)
  local variance = (math.random() - 0.5) * v
  return math.min(math.max(n + variance, 0), 1)
end

local sound_enabled = true -- not settings.startup.mute_drones.value

local make_drone = function(name, tint, item)
  --log(serpent.block{name = name, tint = tint})
  local base = table.deepcopy(data.raw.character.character)

  local random_height = gaussian(90, 10) / 100
  util.recursive_hack_scale(base, random_height)

  local r, g, b = tint.r or tint[1], tint.g or tint[2], tint.b or tint[3]

  if (r > 1 or g > 1 or b > 1) then
    r = r / 255
    g = g / 255
    b = b / 255
  end

  local mask_tint = {r ^ 2, g ^ 2, b ^ 2, shuffle(0.5, 0.5)}
  util.recursive_hack_tint(base, mask_tint, true)

  util.recursive_hack_animation_speed(base.animations[1].mining_with_tool, 1/0.9)

  local random_mining_speed = 1.5 * 1 + ((math.random() - 0.5) / 4)

  util.recursive_hack_animation_speed(base.animations[1].mining_with_tool, 1 / random_mining_speed)

  local bot_name = name
  -- local attack_range = 16
  local bot =
  {
    type = "unit",
    name = bot_name,
    localised_name = { shared.golem_name },
    icon = shared.get_icon_path("iron_golem.png"),
    icon_size = 64,
    icons = {
      {
        icon = shared.get_icon_path("iron_golem.png"),
        icon_size = 64,
      }
    },
    flags = golem_flags,
    map_color = {r ^ 0.5, g ^ 0.5, b ^ 0.5, 0.5},
    enemy_map_color = {r = 1},
    max_health = 2000,
    radar_range = 1,
    order="zzz-"..bot_name,
    --subgroup = "iron-units",
    healing_per_tick = 0.1,
    minable = {result = name, mining_time = 2},
    collision_box = {{-0.18, -0.18}, {0.18, 0.18}},
    collision_mask = golem_collision_mask,
    render_layer = "object",
    --render_layer = "lower-object-above-shadow",
    max_pursue_distance = 64,
    resistances = nil,
    min_persue_time = 60 * 15,
    selection_box = {{-0.6, -0.6}, {0.6, 0.6}},
    sticker_box = {{-0.3, -1}, {0.2, 0.3}},
    distraction_cooldown = (15),
    move_while_shooting = false,
    can_open_gates = true,
    not_controllable = true,
    ai_settings =
    {
      do_separation = false
    },
    attack_parameters =
    {
      type = "projectile",
      ammo_category = "bullet",
      warmup = math.floor(19 * random_mining_speed),
      cooldown = math.floor((26 - 19) * random_mining_speed),
      range = 0.5,
      ammo_type =
      {
        category = "bullet",
        target_type = "entity",
        action =
        {
          type = "direct",
          action_delivery =
          {
            {
              type = "instant",
              target_effects =
              {
                {
                  type = "damage",
                  damage = { amount = shared.mining_damage, type = util.damage_type("physical")}
                }
              }
            }
          }
        }

      },
      animation = base.animations[1].mining_with_tool
    },
    selection_priority = 55,
    vision_distance = 100,
    has_belt_immunity = true,
    affected_by_tiles = true,
    movement_speed = 0.05 * random_height,
    distance_per_frame = 0.05 / random_height,
    pollution_to_join_attack = 1000000,
    corpse = bot_name.."-corpse",
    run_animation = base.animations[1].running,
    rotation_speed = 0.05 / random_height,
    light =
    {
      {
        minimum_darkness = 0.3,
        intensity = 0.4,
        size = 15 * random_height,
        color = {r=1.0, g=1.0, b=1.0}
      },
      {
        type = "oriented",
        minimum_darkness = 0.3,
        picture =
        {
          filename = "__core__/graphics/light-cone.png",
          priority = "extra-high",
          flags = { "light" },
          scale = 2,
          width = 200,
          height = 200
        },
        shift = {0, -7 * random_height},
        size = 1 * random_height,
        intensity = 0.6,
        color = {r=1.0, g=1.0, b=1.0}
      }
    },
    running_sound_animation_positions = {5, 16},
    walking_sound = sound_enabled and
    {
      aggregation =
      {
        max_count = 2,
        remove = true
      },
      variations = sound
    } or nil
  }

  local corpse = util.copy(data.raw["character-corpse"]["character-corpse"])

  util.recursive_hack_tint(corpse, tint, true)
  util.recursive_hack_scale(corpse, random_height)

  corpse.name = bot_name.."-corpse"
  corpse.selectable_in_game = false
  corpse.selection_box = nil
  corpse.render_layer = "remnants"
  corpse.order = "zzz-"..bot_name

  data:extend
  {
    bot,
    corpse
  }
end

--return make_drone

make_drone(shared.golem_name, {1,0,0}, nil)
