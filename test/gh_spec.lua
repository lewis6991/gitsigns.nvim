local helpers = require('test.gs_helpers')

local clear = helpers.clear
local eq = helpers.eq
local exec_lua = helpers.exec_lua

helpers.env()

local function run_gh_case(case)
  return exec_lua(function(case0)
    local async = require('gitsigns.async')
    local cwd = vim.fn.getcwd()
    local calls = {} --- @type string[]
    local repo_view_calls = 0
    local graphql_calls = 0
    local rest_failures = 1
    local original_executable = vim.fn.executable
    local original_system = package.loaded['gitsigns.system']

    local function complete(on_exit, code, stdout, stderr)
      local timer = assert((vim.uv or vim.loop).new_timer())
      timer:start(0, 0, function()
        on_exit({
          code = code,
          stdout = stdout,
          stderr = stderr,
        })
      end)
      return timer
    end

    local function repo_meta()
      return '{"nameWithOwner":"example/test","url":"https://example.test/example/test"}'
    end

    local function graphql_response(sha)
      local nodes = sha == 'hitsha'
          and '[{"url":"https://example.test/pr/42","number":42,"mergedAt":"2026-01-01T00:00:00Z"}]'
        or '[]'
      return ('{"data":{"repository":{"c1":{"associatedPullRequests":{"nodes":%s}}}}}'):format(
        nodes
      )
    end

    local function rest_response(sha)
      if sha == 'hitsha' then
        return '[{"number":42,"url":"https://api.example.test/pulls/42","html_url":"https://example.test/pr/42","merged_at":"2026-01-01T00:00:00Z"}]'
      end
      return '[]'
    end

    local function lookup(gh, sha)
      return async
        .run(function()
          return gh.associated_prs(sha, cwd)
        end)
        :wait(1000)
    end

    local function reload_gh()
      package.loaded['gitsigns.gh'] = nil
      return require('gitsigns.gh')
    end

    local ok, ret = xpcall(function()
      vim.fn.executable = function(cmd)
        if cmd == 'gh' then
          return 1
        end
        return original_executable(cmd)
      end

      package.loaded['gitsigns.system'] = {
        system = function(cmd, _, on_exit)
          if cmd[2] == 'repo' and cmd[3] == 'view' then
            repo_view_calls = repo_view_calls + 1

            if case0 == 'repo-metadata-failure' and repo_view_calls == 1 then
              return complete(on_exit, 1, '', 'gh: HTTP 502')
            end

            return complete(on_exit, 0, repo_meta(), '')
          end

          if cmd[2] == 'api' and cmd[3] == 'graphql' then
            graphql_calls = graphql_calls + 1

            if case0 == 'cache' then
              local sha --- @type string?
              for _, arg in ipairs(cmd) do
                if type(arg) == 'string' and vim.startswith(arg, 'sha1=') then
                  sha = arg:sub(6)
                  break
                end
              end
              calls[#calls + 1] = assert(sha)
              return complete(on_exit, 0, graphql_response(sha), '')
            end

            if case0 == 'rest-fallback' or case0 == 'rest-failure-retry' then
              return complete(on_exit, 1, '', 'gh: HTTP 504')
            end
          end

          local sha = assert(cmd[3]:match('/commits/(.+)/pulls$'))
          calls[#calls + 1] = sha

          if case0 == 'rest-failure-retry' and rest_failures > 0 then
            rest_failures = rest_failures - 1
            return complete(on_exit, 1, '', 'gh: HTTP 502')
          end

          return complete(on_exit, 0, rest_response(sha), '')
        end,
      }

      if case0 == 'cache' then
        local gh = reload_gh()
        local hit1 = lookup(gh, 'hitsha')
        local miss1 = lookup(gh, 'misssha')
        local hit1_cached = lookup(gh, 'hitsha')
        local miss1_cached = lookup(gh, 'misssha')

        gh = reload_gh()

        return {
          calls = calls,
          hit1 = hit1,
          hit1_cached = hit1_cached,
          hit2 = lookup(gh, 'hitsha'),
          miss1 = miss1,
          miss1_cached = miss1_cached,
          miss2 = lookup(gh, 'misssha'),
        }
      end

      local gh = reload_gh()

      if case0 == 'rest-fallback' then
        return {
          calls = calls,
          prs = async
            .run(function()
              return gh.associated_prs_many({ 'hitsha', 'misssha' }, cwd)
            end)
            :wait(1000),
        }
      end

      if case0 == 'rest-failure-retry' then
        return {
          calls = calls,
          first = lookup(gh, 'hitsha'),
          second = lookup(gh, 'hitsha'),
          third = lookup(gh, 'hitsha'),
        }
      end

      if case0 == 'repo-metadata-failure' then
        return {
          first = lookup(gh, 'hitsha'),
          second = lookup(gh, 'hitsha'),
          repo_view_calls = repo_view_calls,
          graphql_calls = graphql_calls,
        }
      end

      error('unknown gh test case: ' .. tostring(case0))
    end, debug.traceback)

    vim.fn.executable = original_executable
    package.loaded['gitsigns.system'] = original_system
    package.loaded['gitsigns.gh'] = nil

    if not ok then
      error(ret)
    end

    return ret
  end, case)
end

describe('gh', function()
  before_each(function()
    clear()
    helpers.chdir_tmp()
    helpers.setup_path()
  end)

  it('caches associated PRs in-session but not across reloads', function()
    local result = run_gh_case('cache')

    eq({ 'hitsha', 'misssha', 'hitsha', 'misssha' }, result.calls)
    eq('42', result.hit1[1].number)
    eq('https://example.test/pr/42', result.hit1[1].url)
    eq('42', result.hit1_cached[1].number)
    eq('42', result.hit2[1].number)
    eq(nil, result.miss1)
    eq(nil, result.miss1_cached)
    eq(nil, result.miss2)
  end)

  it('falls back to REST PR lookup when GraphQL batching fails', function()
    local result = run_gh_case('rest-fallback')

    eq({ 'hitsha', 'misssha' }, result.calls)
    eq('42', result.prs.hitsha[1].number)
    eq('https://example.test/pr/42', result.prs.hitsha[1].url)
    eq(false, result.prs.misssha)
  end)

  it('does not cache failed REST PR lookups as misses', function()
    local result = run_gh_case('rest-failure-retry')

    eq({ 'hitsha', 'hitsha' }, result.calls)
    eq(nil, result.first)
    eq('42', result.second[1].number)
    eq('42', result.third[1].number)
  end)

  it('caches failed repo metadata lookups for the session', function()
    local result = run_gh_case('repo-metadata-failure')

    eq(nil, result.first)
    eq(nil, result.second)
    eq(1, result.repo_view_calls)
    eq(0, result.graphql_calls)
  end)
end)
