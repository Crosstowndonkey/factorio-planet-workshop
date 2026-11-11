-- Planet codes: the text players copy, share and paste.
--
-- A code looks like "PW1:eNq...": "PW", the format version, ":", then base64 of zlib-compressed JSON
-- (exactly what helpers.encode_string(helpers.table_to_json(pack)) makes at runtime).
-- The JSON is a pack: {"planets": [planet, planet, ...]}, so one code can carry one planet or many.
-- The startup setting may hold several codes separated by spaces; anything else in it is ignored.
--
-- Works in both stages (no game API needed), so the loader and the designer share it.

local base64 = require("__planet-workshop__.lib.base64")
local inflate = require("__planet-workshop__.lib.inflate")
local json = require("__planet-workshop__.lib.json")

local M = {}

--- The newest format this version of the mod can read.
M.FORMAT = 1
M.PREFIX = "PW" .. M.FORMAT .. ":"
--- Most planets one game can load from codes (a guard against runaway packs).
M.MAX_PLANETS = 64

--- Decodes one code's body (the part after "PWn:") into a pack table. Returns pack or nil, message.
function M.decode_body(body)
  local ok, result = pcall(function()
    return json.decode(inflate.zlib(base64.decode(body)))
  end)
  if not ok then return nil, tostring(result) end
  if type(result) ~= "table" or type(result.planets) ~= "table" then
    return nil, "not a planet code (no planets in it)"
  end
  return result
end

--- Makes a code from a list of planets (runtime only: needs helpers).
function M.encode(planets)
  return M.PREFIX .. helpers.encode_string(helpers.table_to_json({planets = planets}))
end

--- Short label for a code in messages: its first characters.
local function label(code)
  if #code > 18 then return code:sub(1, 14) .. "..." end
  return code
end

--- Reads every code in a setting text. Returns a list of {planet = table, code = label} and a list of problems.
function M.read_all(text)
  local found, problems = {}, {}
  if type(text) ~= "string" then return found, problems end
  for version, body in text:gmatch("PW(%d+):([A-Za-z0-9+/=]+)") do
    local code = "PW" .. version .. ":" .. body
    if tonumber(version) > M.FORMAT then
      problems[#problems + 1] = {"planet-workshop-problem.newer-format", label(code)}
    elseif tonumber(version) < 1 then
      problems[#problems + 1] = {"planet-workshop-problem.unreadable", label(code), "unknown format"}
    else
      local pack, err = M.decode_body(body)
      if not pack then
        problems[#problems + 1] = {"planet-workshop-problem.unreadable", label(code), err}
      else
        for i = 1, #pack.planets do
          if #found >= M.MAX_PLANETS then
            problems[#problems + 1] = {"planet-workshop-problem.too-many", tostring(M.MAX_PLANETS)}
            return found, problems
          end
          found[#found + 1] = {planet = pack.planets[i], code = label(code)}
        end
      end
    end
  end
  return found, problems
end

return M
