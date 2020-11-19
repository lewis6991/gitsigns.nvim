-- @file        validation.lua
-- @author      Théo Brigitte <theo.brigitte@gmail.com>
-- @contributor Henrique Silva <hensansi@gmail.com>
-- @date        Thu May 28 16:05:15 2015
--
-- @brief       Lua schema validation library.
--
-- Validation is achieved by matching data against a schema.
--
-- A schema is a representation of the expected structure of the data. It is
-- a combination of what we call "validators".
-- Validators are clojures which build accurante validation function for each
-- element of the schema.
-- Meta-validators allow to extend the logic of the schema by providing an
-- additional logic layer around validators.
--  e.g. optional()
--

-- Import from global environment.
local type = type
local pairs = pairs
local print = print
local format = string.format
local floor = math.floor
local insert = table.insert
local next = next


local M = { _NAME = 'validation' }

--- Generate error message for validators.
--
-- @param data mixed
--   Value that failed validation.
-- @param expected_type string
--   Expected type for data
--
-- @return
--   String describing the error.
---
local function error_message(data, expected_type)
  if data then
    return format('is not %s.', expected_type)
  end

  return format('is missing and should be %s.', expected_type)
end

--- Create a readable string output from the validation errors output.
--
-- @param error_list table
--   Nested table identifying where the error occured.
--   e.g. { price = { rule_value = 'error message' } }
-- @param parents string
--   String of dot separated parents keys
--
-- @return string
--   Message describing where the error occured. e.g. price.rule_value = "error message"
---
function M.print_err(error_list, parents)
  -- Makes prefix not nil, for posterior concatenation.
  local error_output = ''
  local parents = parents or ''
  if not error_list then return false end
  -- Iterates over the list of messages.
  for key, err in pairs(error_list) do
    -- If it is a node, print it.
    if type(err) == 'string' then
      error_output = format('%s\n%s%s %s', error_output, parents ,key, err)
    else
      -- If it is a table, recurse it.
      error_output = format('%s%s', error_output, M.print_err(err, format('%s%s.', parents, key)))
    end
  end

  return error_output
end

--- Validators.
--
-- A validator is a function in charge of verifying data compliance.
--
-- Prototype:
-- @key
--   Key of data being validated.
-- @data
--   Current data tree level. Meta-validator might need to verify other keys. e.g. assert()
--
-- @return
--   true on success, false and message describing the error
---


--- Generates string validator.
--
-- @return
--   String validator function.
---
function M.is_string()
  return function(value)
    if type(value) ~= 'string' then
      return false, error_message(value, 'a string')
    end
    return true
  end
end

--- Generates integer validator.
--
-- @return
--   Integer validator function.
---
function M.is_integer()
  return function(value)
    if type(value) ~= 'number' or value%1 ~= 0 then
      return false, error_message(value, 'an integer')
    end
    return true
  end
end

--- Generates number validator.
--
-- @return
--   Number validator function.
---
function M.is_number()
  return function(value)
    if type(value) ~= 'number' then
      return false, error_message(value, 'a number')
    end
    return true
  end
end

--- Generates boolean validator.
--
-- @return
--   Boolean validator function.
---
function M.is_boolean()
  return function(value)
    if type(value) ~= 'boolean' then
      return false, error_message(value, 'a boolean')
    end
    return true
  end
end

--- Generates an array validator.
--
-- Validate an array by applying same validator to all elements.
--
-- @param validator function
--   Function used to validate the values.
-- @param is_object boolean (optional)
--   When evaluted to false (default), it enforce all key to be of type number.
--
-- @return
--   Array validator function.
--   This validator return value is either true on success or false and
--   a table holding child_validator errors.
---
function M.is_array(child_validator, is_object)
  return function(value, key, data)
    local result, err = nil
    local err_array = {}

    -- Iterate the array and validate them.
    if type(value) == 'table' then
      for index in pairs(value) do
        if not is_object and type(index) ~= 'number' then
          insert(err_array, error_message(value, 'an array') )
        else
          result, err = child_validator(value[index], index, value)
          if not result then
            err_array[index] = err
          end
        end
      end
    else
      insert(err_array, error_message(value, 'an array') )
    end

    if next(err_array) == nil then
      return true
    else
      return false, err_array
    end
  end
end

--- Generates optional validator.
--
-- When data is present apply the given validator on data.
--
-- @param validator function
--   Function used to validate value.
--
-- @return
--   Optional validator function.
--   This validator return true or the result from the given validator.
---
function M.optional(validator)
  return function(value, key, data)
    if not value then return true
    else
      return validator(value, key, data)
    end
  end
end

--- Generates or meta validator.
--
-- Allow data validation using two different validators and applying
-- or condition between results.
--
-- @param validator_a function
--   Function used to validate value.
-- @param validator_b function
--   Function used to validate value.
--
-- @return
--   Or validator function.
--   This validator return true or the result from the given validator.
---
function M.or_op(validator_a, validator_b)
  return function(value, key, data)
    if not value then return true
    else
      local valid, err_a = validator_a(value, key, data)
      if not valid then
        valid, err_b = validator_b(value, key, data)
      end
      if not valid then
        return valid, err_a .. " OR " .. err_b
      else
        return valid, nil
      end
    end
  end
end

--- Generates assert validator.
--
-- This function enforces the existence of key/value with the
-- verification of the key_check.
--
-- @param key_check mixed
--   Key used to check the optionality of the asserted key.
-- @param match mixed
--   Comparation value.
-- @param validator function
--   Function that validates the type of the data.
--
-- @return
--   Assert validator function.
--   This validator return true, the result from the given validator or false
--   when the assertion fails.
---
function M.assert(key_check, match, validator)
  return function(value, key, data)
    if data[key_check] == match then
      return validator(value, key, data)
    else
      return true
    end
  end
end

--- Generates list validator.
--
-- Ensure the value is contained in the given list.
--
-- @param list table
--   Set of allowed values.
-- @param value mixed
--   Comparation value.
-- @param validator function
--   Function that validates the type of the data.
--
-- @return
--   In list validator function.
---
function M.in_list(list)
  return function(value)
    local printed_list = "["
    for _, word in pairs(list) do
      if word == value then
        return true
      end
      printed_list = printed_list .. " '" .. word .. "'"
    end

    printed_list = printed_list .. " ]"
    return false, { error_message(value, 'in list ' .. printed_list) }
  end
end

--- Generates table validator.
--
-- Validate table data by using appropriate schema.
--
-- @param schema table
--   Schema used to validate the table.
--
-- @return
--   Table validator function.
--   This validator return value is either true on success or false and
--   a nested table holding all errors.
---
function M.is_table(schema, tolerant)
  return function(value)
    local result, err = nil

    if type(value) ~= 'table' then
      -- Enforce errors of childs value.
      _, err = validate_table({}, schema, tolerant)
      if not err then err = {} end
      result = false
      insert(err, error_message(value, 'a table') )
    else
      result, err = validate_table(value, schema, tolerant)
    end

    return result, err
  end
end

--- Validate function.
--
-- @param data
--   Table containing the pairs to be validated.
-- @param schema
--   Schema against which the data will be validated.
--
-- @return
--   String describing the error or true.
---
function validate_table(data, schema, tolerant)

  -- Array of error messages.
  local errs = {}
  -- Check if the data is empty.

  -- Check if all data keys are present in the schema.
  if not tolerant then
    for key in pairs(data) do
      if schema[key] == nil then
        errs[key] = 'is not allowed.'
      end
    end
  end

   -- Iterates over the keys of the data table.
  for key in pairs(schema) do
    -- Calls a function in the table and validates it.
    local result, err = schema[key](data[key], key, data)

    -- If validation fails, print the result and return it.
    if not result then
      errs[key] = err
    end
  end

  -- Lua does not give size of table holding only string as keys.
  -- Despite the use of #table we have to manually loop over it.
  for _ in pairs(errs) do
    return false, errs
  end

  return true
end

return M

