This is a web application written using the Phoenix web framework.

## Related projects

- **Frontend (React)**: The frontend application is located at `/home/jurusysadmin/chat/frontend`

## Makefile targets

The project uses a Makefile (`make <target>`) for deployment and service management.

### Deployment
- `setup` — Full first-time deploy: builds release (as project user), copies to `/opt/chat`, installs systemd service, runs migrations, starts the service (requires sudo)
- `deploy` — Same as `setup` (alias)
- `build` — Build production release locally (`MIX_ENV=prod mix release chat`)
- `copy` — `build` + copy release to `/opt/chat`

### Service management (all require sudo)
- `start` / `stop` / `restart` — systemd service control
- `status` — Show service status
- `reload` — systemd daemon-reload
- `enable` / `disable` — Enable/disable on boot

### Logs
- `logs` — Last 100 lines of service logs
- `logs-live` — Follow logs in real-time
- `logs-error` — Only error-level logs

### Database (FreeBSD sources `/usr/local/etc/chat.env` for config)
- `migrate` — Run pending migrations via `Chat.Release.migrate()`
- `rollback` — Rollback last migration
- `seed` — Run seed data

### Remote access
- `remote` — Open remote Elixir console on the running node
- `remote-iex` — Open remote IEx session

### Hot-swap upgrade (zero-downtime, uses BEAM release_handler)
- **Workflow**: bump version in `mix.exs` → `make build-upgrade` → `make deploy-upgrade`
- `build-upgrade` — Build upgrade release with `--upgrade` flag. Requires previous release in `_build/prod/rel/chat/releases/`
- `deploy-upgrade` — Copies upgrade tarball to `/opt/chat`, runs migrations, then hot-swaps the running node via `release_handler.install_release/1` + `make_permanent/1`. No service restart required.

### Local development
- `dev` — Start Phoenix dev server (`mix phx.server`)
- `setup-local` — Get dependencies and setup DB

### Utilities
- `version` — Show app version from `mix.exs`
- `check` — Run `mix precommit` (lint + format + test)
- `format` — Run `mix format`
- `clean` — Remove `_build` and `deps` directories
- `backup-db` — pg_dump database to `/opt/chat/backup_<timestamp>.sql`

### Important notes for AI agents
- `deploy-upgrade` depends on `build-upgrade` — run them separately or together
- Migrations must be **backward-compatible** for hot-swap (old code runs alongside new)
- The FreeBSD environment file `/usr/local/etc/chat.env` is required for all database/remote commands
- Always use `set -a` before `source` when reading `/usr/local/etc/chat.env` in shell (variables need export to child processes)
- The cookie for Erlang distribution is set via `RELEASE_COOKIE` in `/usr/local/etc/chat.env` and must match across build+run for RPC to work

### Version management
- The canonical version is defined in `mix.exs`, field `version: "0.1.0"`
- Releases are stored in `/opt/chat/releases/<version>/` — each version has its own subdirectory
- The current running version is tracked by `start_erl.data` in the releases root
- **Workflow**: bump version in `mix.exs` → `make build-upgrade` → `make deploy-upgrade`
- Version must be bumped **before** building the upgrade release. The `--upgrade` flag reads the previous release from `_build/prod/rel/chat/releases/` to generate the `relup` file
- Use `make version` to display the current version from `mix.exs`

### Bump targets (when to use each)

- `make bump-patch` — **Bug fixes, refactors, small tweaks**. No new functionality or breaking changes. Example: `0.1.0` → `0.1.1`
- `make bump-minor` — **New features, backward-compatible additions**. Public API additions that don't break existing consumers. Example: `0.1.0` → `0.2.0`
- `make bump-major` — **Breaking changes**. Schema changes, removed API endpoints, incompatible config changes. Example: `0.1.0` → `1.0.0`

**Note**: The bump targets only update `mix.exs`. You still need to run `make build-upgrade && make deploy-upgrade` to build and deploy the new version.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines


- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- >
## Elixir engineering reference-start-->

- Before implementing, debugging, or reviewing Elixir code, read
  `docs/ELIXIR_GUIDELINES.md`.
- When uncertain about language behavior, APIs, OTP, Tasks, processes,
  supervision, protocols, macros, or types, consult:
  `https://elixir.hexdocs.pm/llms.txt`.
- Read only the documentation relevant to the current task.
- This `AGENTS.md` takes precedence over `docs/ELIXIR_GUIDELINES.md` when
  instructions conflict.

<!-- >
## Elixir engineering reference-end-->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->


<!-- postgres-start -->
## PostgreSQL engineering reference

- Before designing schemas, writing migrations, adding indexes, optimizing
  queries, or changing database behavior, read
  `docs/POSTGRES_GUIDELINES.md`.
- Use the `ecto-thinking` skill for Ecto application-layer decisions.
- Use PostgreSQL guidelines for schema design, indexes, query plans,
  transactions, locking, constraints, connection management, and operations.
- Verify version-specific PostgreSQL behavior against the official
  documentation for the version used by the project.
- Never perform destructive database operations or production migrations
  without explicit authorization.
- This `AGENTS.md` takes precedence when instructions conflict.
<!-- postgres-end -->

<!-- usage-rules-end -->