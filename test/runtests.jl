ENV["QUICKENV_DISABLE_AUTO"] = "true"
using QuickEnv
using Test
using Pkg
using TOML

const QUICKENV_TEST_DEPOT = mktempdir()
pushfirst!(DEPOT_PATH, QUICKENV_TEST_DEPOT)

@testset "QuickEnv.jl Tests" begin
    @testset "Script Metadata Parsing" begin
        # Write a mock Julia script with magic comments (inline)
        mock_script_content = (
            "#!/usr/bin/env julia\n\n" *
            "using QuickEnv # fallback: plotting_test, exclude: global, outdated_plotting, broken_env, silent, create: data_test, description: \"Inline test description\"\n" *
            "using Plots\n" *
            "import DataFrames: DataFrame\n\n" *
            "# Some comments that shouldn't impact parsing:\n" *
            "# using NotAPackage\n" *
            "# import AlsoNotAPackage\n"
        )

        # Create a temporary file
        tmp_path, io = mktemp()
        try
            write(io, mock_script_content)
            close(io)

            # Parse the metadata
            pkgs, fallback, excluded, is_verbose, is_silent, create_env, description, is_local = QuickEnv.parse_script_metadata(
                tmp_path
            )

            # Verify package extraction
            @test "QuickEnv" in pkgs
            @test "Plots" in pkgs
            @test "DataFrames" in pkgs
            @test !("NotAPackage" in pkgs)
            @test !("AlsoNotAPackage" in pkgs)
            @test length(pkgs) == 3

            # Verify fallback extraction
            @test fallback == "plotting_test"

            # Verify exclusion extraction
            @test "global" in excluded
            @test "outdated_plotting" in excluded
            @test "broken_env" in excluded
            @test length(excluded) == 3

            # Verify silent extraction from inline comment
            @test is_silent == true

            # Verify create extraction from inline comment
            @test create_env == "data_test"

            # Verify description extraction from inline comment
            @test description == "Inline test description"
            @test is_local == false
        finally
            # Clean up the temp file
            rm(tmp_path)
        end

        # Test Submodule / sub-path import parsing
        mock_script_submod = """
        #!/usr/bin/env julia
        using QuickEnv # silent
        using HTTP.WebSockets
        import DataFrames.DataFrame
        """
        tmp_path_sub, io_sub = mktemp()
        try
            write(io_sub, mock_script_submod)
            close(io_sub)

            pkgs_sub, _, _, _, _, _, _, _ = QuickEnv.parse_script_metadata(tmp_path_sub)
            @test "HTTP" in pkgs_sub
            @test "DataFrames" in pkgs_sub
            @test !("HTTP.WebSockets" in pkgs_sub)
            @test !("DataFrames.DataFrame" in pkgs_sub)
        finally
            rm(tmp_path_sub, force=true)
        end

        # Imports and directives inside string literals are data, not source code.
        mock_script_string = """
        using QuickEnv # silent
        fixture = \"\"\"
        using FakePackage
        using QuickEnv # create: must_not_exist, desc: dangerous
        \"\"\"
        using
            Dates
        """
        tmp_path_string, io_string = mktemp()
        try
            write(io_string, mock_script_string)
            close(io_string)
            string_pkgs, _, _, _, silent_string, create_string, desc_string, _ =
                QuickEnv.parse_script_metadata(tmp_path_string)
            @test string_pkgs == ["QuickEnv", "Dates"]
            @test silent_string
            @test isempty(create_string)
            @test isempty(desc_string)
        finally
            rm(tmp_path_string, force=true)
        end

        # Test Inline verbose parsing
        mock_script_verbose = "#!/usr/bin/env julia\n" * "using QuickEnv # verbose\n"
        tmp_path_v, io_v = mktemp()
        try
            write(io_v, mock_script_verbose)
            close(io_v)

            _, _, _, is_verbose_v, _, _, _, _ = QuickEnv.parse_script_metadata(tmp_path_v)
            @test is_verbose_v == true
        finally
            rm(tmp_path_v)
        end

        # Test Inline local parsing
        mock_script_local = "#!/usr/bin/env julia\n" * "using QuickEnv # local\n"
        tmp_path_l, io_l = mktemp()
        try
            write(io_l, mock_script_local)
            close(io_l)

            _, _, _, _, _, _, _, is_local_l = QuickEnv.parse_script_metadata(tmp_path_l)
            @test is_local_l == true
        finally
            rm(tmp_path_l)
        end

        # Test Standalone QuickEnv.create parsing
        mock_script_standalone = """
        #!/usr/bin/env julia
        # QuickEnv.create: data_test_standalone
        using QuickEnv
        """
        tmp_path_s, io_s = mktemp()
        try
            write(io_s, mock_script_standalone)
            close(io_s)

            _, _, _, _, _, create_env_s, _, _ = QuickEnv.parse_script_metadata(tmp_path_s)
            @test create_env_s == "data_test_standalone"
        finally
            rm(tmp_path_s)
        end

        # Test Standalone QuickEnv.description parsing
        mock_script_standalone_desc = """
        #!/usr/bin/env julia
        # QuickEnv.description: Standalone test description
        using QuickEnv
        """
        tmp_path_d, io_d = mktemp()
        try
            write(io_d, mock_script_standalone_desc)
            close(io_d)

            _, _, _, _, _, _, description_d, _ = QuickEnv.parse_script_metadata(tmp_path_d)
            @test description_d == "Standalone test description"
        finally
            rm(tmp_path_d)
        end

        # Test Standalone QuickEnv.desc parsing
        mock_script_standalone_desc_short = """
        #!/usr/bin/env julia
        # QuickEnv.desc: Standalone short desc test
        using QuickEnv
        """
        tmp_path_d2, io_d2 = mktemp()
        try
            write(io_d2, mock_script_standalone_desc_short)
            close(io_d2)

            _, _, _, _, _, _, description_d2, _ = QuickEnv.parse_script_metadata(
                tmp_path_d2
            )
            @test description_d2 == "Standalone short desc test"
        finally
            rm(tmp_path_d2)
        end

        # Test Inline desc parsing
        mock_script_inline_desc_short = """
        #!/usr/bin/env julia
        using QuickEnv # desc: "Inline short desc test"
        """
        tmp_path_d3, io_d3 = mktemp()
        try
            write(io_d3, mock_script_inline_desc_short)
            close(io_d3)

            _, _, _, _, _, _, description_d3, _ = QuickEnv.parse_script_metadata(
                tmp_path_d3
            )
            @test description_d3 == "Inline short desc test"
        finally
            rm(tmp_path_d3)
        end

        # Test Standalone quickenv_fallback with desc option
        mock_script_fallback_with_desc = """
        #!/usr/bin/env julia
        # quickenv_fallback: plotting_test, desc: "Fallback desc test"
        using QuickEnv
        """
        tmp_path_f, io_f = mktemp()
        try
            write(io_f, mock_script_fallback_with_desc)
            close(io_f)

            _, fallback_env_f, _, _, _, _, description_f, _ = QuickEnv.parse_script_metadata(
                tmp_path_f
            )
            @test fallback_env_f == "plotting_test"
            @test description_f == "Fallback desc test"
        finally
            rm(tmp_path_f)
        end

        # Test Standalone QuickEnv.create with desc option
        mock_script_create_with_desc = """
        #!/usr/bin/env julia
        # QuickEnv.create: data_test, desc: "Create desc test"
        using QuickEnv
        """
        tmp_path_c, io_c = mktemp()
        try
            write(io_c, mock_script_create_with_desc)
            close(io_c)

            _, _, _, _, _, create_env_c, description_c, _ = QuickEnv.parse_script_metadata(
                tmp_path_c
            )
            @test create_env_c == "data_test"
            @test description_c == "Create desc test"
        finally
            rm(tmp_path_c)
        end

        # Test Recursive include scanning
        tdir = mktempdir()
        try
            helper_file = joinpath(tdir, "helper.jl")
            main_file = joinpath(tdir, "main.jl")

            write(helper_file, "using JSON\nusing Dates\n")
            write(
                main_file, "using QuickEnv # silent\nusing Plots\ninclude(\"helper.jl\")\n"
            )

            inc_pkgs, _, _, _, _, _, _, _ = QuickEnv.parse_script_metadata(main_file)
            @test "QuickEnv" in inc_pkgs
            @test "Plots" in inc_pkgs
            @test "JSON" in inc_pkgs
            @test "Dates" in inc_pkgs
            @test length(inc_pkgs) == 4
        finally
            rm(tdir, recursive=true, force=true)
        end
    end

    @testset "Project.toml Description Write" begin
        tmp_toml, io_t = mktemp()
        try
            close(io_t)
            # Write description
            QuickEnv.update_description(tmp_toml, "Initial Description")
            content = read(tmp_toml, String)
            @test occursin("description = \"Initial Description\"", content)

            # Update description
            QuickEnv.update_description(tmp_toml, "Updated Description")
            content = read(tmp_toml, String)
            @test occursin("description = \"Updated Description\"", content)
            @test !occursin("description = \"Initial Description\"", content)
        finally
            rm(tmp_toml)
        end
    end

    @testset "Environment Search" begin
        # Calling the matching functions with no required packages should return all environments
        all_envs = QuickEnv.find_matching_envs(String[])
        @test isa(all_envs, Vector{String})

        # Test search with non-existent package should return a subset or empty list
        rare_envs = QuickEnv.find_matching_envs(["NonExistentPackage9999"])
        @test isempty(rare_envs)
    end

    @testset "Environment Filtering Logic (Magic Comments)" begin
        mock_matching = ["v1.12", "plotting", "data", "broken_env"]

        # 1. Global environments are never automatic matches.
        res1 = QuickEnv.filter_matching_envs(copy(mock_matching), "", String[])
        @test res1 == ["plotting", "data", "broken_env"]

        # 2. Fallback Override: Fallback name specified forces standard global (v1.12) to be ignored
        res2 = QuickEnv.filter_matching_envs(copy(mock_matching), "plotting", String[])
        @test "plotting" in res2
        @test !("v1.12" in res2)

        # 3. Global Exclusion: Excluding 'global' filters standard versioned environments
        res3 = QuickEnv.filter_matching_envs(copy(mock_matching), "", ["global"])
        @test "plotting" in res3
        @test "data" in res3
        @test !("v1.12" in res3)

        # 4. Explicit Exclusions: Filters specific custom environment names
        res4 = QuickEnv.filter_matching_envs(
            copy(mock_matching), "", ["broken_env", "plotting"]
        )
        @test !("v1.12" in res4)
        @test "data" in res4
        @test !("broken_env" in res4)
        @test !("plotting" in res4)
    end

    @testset "Ignored Local Project/Manifest Warning" begin
        # Create a temp directory to simulate a script directory with Project.toml
        tmp_dir = mktempdir()
        try
            script_path = joinpath(tmp_dir, "script.jl")
            local_proj = joinpath(tmp_dir, "Project.toml")
            touch(local_proj)

            # 1. Non-silent mode: should emit a warning log
            @test_logs (:warn, r"QuickEnv: Local Project.toml or Manifest.toml exists.*") begin
                QuickEnv.warn_ignored_local_files(script_path, "plotting_test", false)
            end

            # 2. Silent mode: should emit no warning or info logs
            @test_logs begin
                QuickEnv.warn_ignored_local_files(script_path, "plotting_test", true)
            end
        finally
            rm(tmp_dir, recursive=true, force=true)
        end
    end

    @testset "Verbose Mode vs Default Silent Behavior" begin
        # 1. Default (is_verbose=false): activation is completely silent
        Pkg.activate(; temp=true, io=devnull)
        @test_logs begin
            QuickEnv.activate_matched_env(["plotting"], false)
        end

        # 2. Verbose (is_verbose=true): activation prints info log
        Pkg.activate(; temp=true, io=devnull)
        @test_logs (:info, r"QuickEnv: Found matching environment @plotting.*"s) begin
            QuickEnv.activate_matched_env(["plotting"], true)
        end
    end

    @testset "Package Casing and Typo Diagnosis" begin
        # 1. Levenshtein distance tests
        @test QuickEnv.levenshtein_distance("Plots", "Plots") == 0
        @test QuickEnv.levenshtein_distance("plots", "Plots") == 1
        @test QuickEnv.levenshtein_distance("Pltos", "Plots") == 2
        @test QuickEnv.levenshtein_distance("cairo", "Cairo") == 1

        # 2. Known local packages discovery (stdlibs are always present)
        local_pkgs = QuickEnv.get_known_local_packages()
        @test "Base" in local_pkgs
        @test "LinearAlgebra" in local_pkgs

        # 3. Warning on casing mismatch (stdlibs)
        @test_logs (:warn, r"incorrect casing.*LinearAlgebra"s) begin
            QuickEnv.diagnose_and_suggest_packages(["linearalgebra"], false)
        end

        # 4. Warning on typo (e.g. 'Dats' -> 'Dates')
        @test_logs (:warn, r"Did you mean 'Dates'"s) begin
            QuickEnv.diagnose_and_suggest_packages(["Dats"], false)
        end

        # 4b. Warning on prefix/truncation (e.g. 'LinearAlg' -> 'LinearAlgebra')
        @test_logs (:warn, r"Did you mean 'LinearAlgebra'"s) begin
            QuickEnv.diagnose_and_suggest_packages(["LinearAlg"], false)
        end

        # 5. Fast path: no warnings on valid stdlib packages
        @test_logs begin
            QuickEnv.diagnose_and_suggest_packages(["LinearAlgebra", "Dates"], false)
        end

        # 6. Silent mode: no warnings even if typos exist
        @test_logs begin
            QuickEnv.diagnose_and_suggest_packages(["linearalgebra", "Dats"], true)
        end
    end

    @testset "Canonical Key & Hashing Engine" begin
        k1 = QuickEnv.get_canonical_key(["Plots", "Cairo"])
        k2 = QuickEnv.get_canonical_key(["Cairo", "Plots", "Plots"])
        @test k1 == "Cairo+Plots"
        @test k2 == "Cairo+Plots"
        @test k1 == k2

        h1 = QuickEnv.get_cache_hash(k1)
        h2 = QuickEnv.get_cache_hash(k2)
        @test !isempty(h1)
        @test length(h1) == 12
        @test h1 == h2

        h3 = QuickEnv.get_cache_hash("DataFrames+CSV")
        @test h3 != h1
        @test !isempty(QuickEnv.get_cache_hash(""))
        @test !isempty(QuickEnv.get_cache_hash("X"))
    end

    @testset "Bitmask Greedy Set-Cover Engine" begin
        req = ["Plots", "Cairo", "DataFrames", "CSV", "JSON"]
        candidates = [
            ("plotting", ["Plots", "Cairo"]),
            ("data", ["DataFrames", "CSV"]),
            ("utils", ["JSON", "Dates"]),
            ("unrelated", ["Flux", "CUDA"]),
            (
                "mega",
                ["Plots", "Cairo", "DataFrames", "CSV", "JSON", "Flux", "Zygote", "CUDA"],
            ),
        ]

        # Exact objective: fewest environments first, then fewest extraneous packages.
        selected = QuickEnv.find_minimal_covering_envs(req, candidates)
        @test selected == ["mega"]
        @test !("unrelated" in selected)
        @test length(selected) == 1

        # A classic greedy counterexample still returns the exact two-set cover.
        exact_req = ["1", "2", "3", "4", "5", "6"]
        exact_candidates = [
            ("greedy_trap", ["1", "2", "3", "4"]),
            ("left", ["1", "2", "5"]),
            ("right", ["3", "4", "6"]),
        ]
        @test Set(QuickEnv.find_minimal_covering_envs(exact_req, exact_candidates)) ==
            Set(["left", "right"])

        compatible = QuickEnv.find_minimal_covering_envs(
            ["A", "B"],
            [("bad_a", ["A"]), ("bad_b", ["B"]), ("good_a", ["A"]), ("good_b", ["B"])];
            compatibility_check=envs -> !any(startswith(env, "bad") for env in envs),
        )
        @test Set(compatible) == Set(["good_a", "good_b"])

        # Test timeout guard (timeout_sec = 0.0 forces immediate timeout return)
        timeout_selected = QuickEnv.find_minimal_covering_envs(
            req, candidates; timeout_sec=0.0
        )
        @test isempty(timeout_selected)
    end

    @testset "Optimization A: Partial Set-Cover Engine" begin
        req = ["Plots", "Cairo", "DataFrames", "CSV", "UncoveredPkg"]
        candidates = [
            ("plotting", ["Plots", "Cairo"]),
            ("data", ["DataFrames", "CSV"]),
            ("bloated", ["Plots", "Cairo", "DataFrames", "CSV", "UnrelatedA", "UnrelatedB"]),
        ]

        # 1. Complete cover should fail (UncoveredPkg is missing from all)
        complete = QuickEnv.find_minimal_covering_envs(req, candidates)
        @test isempty(complete)

        # 2. Strict subset partial cover should select plotting and data (ignoring bloated)
        partial, covered = QuickEnv.find_partial_covering_envs(req, candidates; strict_subset=true)
        @test "plotting" in partial
        @test "data" in partial
        @test !("bloated" in partial)
        @test length(partial) == 2
        @test length(covered) == 4
        @test !("UncoveredPkg" in covered)
        @test "Plots" in covered
        @test "DataFrames" in covered

        # 3. Timeout guard
        timeout_partial, timeout_cov = QuickEnv.find_partial_covering_envs(
            req, candidates; timeout_sec=0.0
        )
        @test isempty(timeout_partial)
        @test isempty(timeout_cov)
    end

    @testset "Deterministic Manifest Transitive Compatibility & Stitching" begin
        # Create isolated mock environments in a temporary depot
        tdir = mktempdir()
        try
            old_depot = copy(DEPOT_PATH)
            empty!(DEPOT_PATH)
            push!(DEPOT_PATH, tdir)

            env_base = joinpath(tdir, "environments")
            env_plot = joinpath(env_base, "mock_plot")
            env_data = joinpath(env_base, "mock_data")
            mkpath(env_plot)
            mkpath(env_data)

            write(
                joinpath(env_plot, "Project.toml"),
                """
[deps]
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
""",
            )
            write(
                joinpath(env_plot, "Manifest.toml"),
                """
julia_version = "$(VERSION)"
manifest_format = "2.0"

[deps]
[[deps.Plots]]
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.40.0"
git-tree-sha1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
""",
            )

            write(
                joinpath(env_data, "Project.toml"),
                """
[deps]
DataFrames = "a93c0a0b-4844-5373-a966-813e8a4b615c"
""",
            )
            write(
                joinpath(env_data, "Manifest.toml"),
                """
julia_version = "$(VERSION)"
manifest_format = "2.0"

[deps]
[[deps.DataFrames]]
uuid = "a93c0a0b-4844-5373-a966-813e8a4b615c"
version = "1.6.0"
git-tree-sha1 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
""",
            )

            try
                compat, deps, m_deps = QuickEnv.check_manifest_compat([
                    "mock_plot", "mock_data"
                ])
                @test compat == true
                @test haskey(deps, "Plots")
                @test haskey(deps, "DataFrames")

                # Test fast stitching
                target_env = "test_auto_unit_stitch"
                stitched = QuickEnv.stitch_environments(
                    target_env, ["mock_plot", "mock_data"], true
                )
                @test stitched == true

                target_proj = joinpath(
                    DEPOT_PATH[1], "environments", target_env, "Project.toml"
                )
                @test isfile(target_proj)
                target_manifest = joinpath(dirname(target_proj), "Manifest.toml")
                parsed_manifest = TOML.parsefile(target_manifest)
                @test parsed_manifest["deps"]["Plots"] isa Vector
                @test parsed_manifest["deps"]["DataFrames"] isa Vector
                @test Pkg.Types.EnvCache(target_proj) isa Pkg.Types.EnvCache

                # Existing auto environments are immutable; differing content is
                # treated as an identity collision rather than overwritten.
                write(target_proj, "[deps]\n")
                @test !QuickEnv.stitch_environments(
                    target_env, ["mock_plot", "mock_data"], true
                )
            finally
                empty!(DEPOT_PATH)
                append!(DEPOT_PATH, old_depot)
            end
        finally
            rm(tdir; recursive=true, force=true)
        end
    end

    @testset "Stitch Environments Failure Path (Conflict Detection)" begin
        tdir = mktempdir()
        try
            old_depot = copy(DEPOT_PATH)
            empty!(DEPOT_PATH)
            push!(DEPOT_PATH, tdir)

            env_base = joinpath(tdir, "environments")
            env_a = joinpath(env_base, "conflict_a")
            env_b = joinpath(env_base, "conflict_b")
            mkpath(env_a)
            mkpath(env_b)

            write(
                joinpath(env_a, "Project.toml"),
                """
[deps]
Foo = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
""",
            )
            write(
                joinpath(env_a, "Manifest.toml"),
                """
julia_version = "$(VERSION)"
manifest_format = "2.0"

[deps]
[[deps.Foo]]
uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
version = "1.0.0"
""",
            )

            write(
                joinpath(env_b, "Project.toml"),
                """
[deps]
Foo = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
""",
            )
            write(
                joinpath(env_b, "Manifest.toml"),
                """
julia_version = "$(VERSION)"
manifest_format = "2.0"

[deps]
[[deps.Foo]]
uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
version = "2.0.0"
""",
            )

            try
                compat, _, _ = QuickEnv.check_manifest_compat(["conflict_a", "conflict_b"])
                @test compat == false

                result = QuickEnv.stitch_environments(
                    "test_fail_stitch", ["conflict_a", "conflict_b"], true
                )
                @test result == false
            finally
                empty!(DEPOT_PATH)
                append!(DEPOT_PATH, old_depot)
            end
        finally
            rm(tdir; recursive=true, force=true)
        end
    end

    @testset "State-Aware Cache Engine" begin
        function write_cache_fixture(env_name)
            env_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
            mkpath(env_dir)
            write(joinpath(env_dir, "Project.toml"), "[deps]\n")
            write(
                joinpath(env_dir, "Manifest.toml"),
                "julia_version = \"$(VERSION)\"\nmanifest_format = \"2.0\"\n[deps]\n",
            )
            return env_dir
        end

        # 1. Update cache entry
        req = ["Plots", "DataFrames"]
        source_dir = write_cache_fixture("plotting")
        QuickEnv.update_cache_entry(req, "test_cache_target", ["plotting"])

        # 2. Check cache hit
        hit = QuickEnv.check_cache_hit(req)
        # Target dir doesn't exist so should return nothing
        @test hit === nothing

        # Create target dir and test hit
        target_dir = write_cache_fixture("test_cache_target")
        try
            QuickEnv.update_cache_entry(req, "test_cache_target", ["plotting"])
            hit2 = QuickEnv.check_cache_hit(req)
            @test hit2 == "test_cache_target"
        finally
            rm(target_dir, recursive=true, force=true)
            rm(source_dir, recursive=true, force=true)
        end

        # 3. Corrupted cache entry with mismatched sources / mtimes
        cache = QuickEnv.load_cache()
        bad_key = QuickEnv.get_canonical_key(["FakePackageA", "FakePackageB"])
        target_corrupt = joinpath(DEPOT_PATH[1], "environments", "test_corrupt_cache")
        mkpath(target_corrupt)
        try
            cache[bad_key] = Dict(
                "env" => "test_corrupt_cache",
                "sources" => ["env1", "env2"],
                "source_digests" => ["bad"],
                "target_digest" => "bad",
                "updated_at" => string(time()),
            )
            QuickEnv.save_cache(cache)

            hit_corrupt = QuickEnv.check_cache_hit(["FakePackageA", "FakePackageB"])
            @test hit_corrupt === nothing
        finally
            rm(target_corrupt; recursive=true, force=true)
            cache2 = QuickEnv.load_cache()
            delete!(cache2, bad_key)
            QuickEnv.save_cache(cache2)
        end

        # 4. Script-level cache and failure invalidation
        mock_script_path = tempname() * ".jl"
        write(mock_script_path, "using QuickEnv\n")
        try
            QuickEnv.update_script_cache_entry(mock_script_path, "auto_script_test")
            c_data = QuickEnv.load_cache()
            @test haskey(c_data, "scripts")
            @test haskey(c_data["scripts"], mock_script_path)
            @test c_data["scripts"][mock_script_path]["env"] == "auto_script_test"
            @test c_data["scripts"][mock_script_path]["files"] == [mock_script_path]
            @test length(c_data["scripts"][mock_script_path]["digests"]) == 1

            @test QuickEnv.check_script_cache_hit(mock_script_path) === nothing

            # Invalidate
            QuickEnv.invalidate_script_cache(mock_script_path)
            c_data_after = QuickEnv.load_cache()
            @test !haskey(get(c_data_after, "scripts", Dict()), mock_script_path)
        finally
            rm(mock_script_path, force=true)
        end


        # Included files participate in script-cache identity.
        include_dir = mktempdir()
        include_target = write_cache_fixture("auto_script_include_test")
        main_script = joinpath(include_dir, "main.jl")
        helper_script = joinpath(include_dir, "helper.jl")
        write(main_script, "using QuickEnv\ninclude(\"helper.jl\")\n")
        write(helper_script, "using Dates\n")
        try
            QuickEnv.update_script_cache_entry(main_script, "auto_script_include_test")
            @test QuickEnv.check_script_cache_hit(main_script) == "auto_script_include_test"
            write(helper_script, "using Dates, Random\n")
            @test QuickEnv.check_script_cache_hit(main_script) === nothing
        finally
            rm(include_dir; recursive=true, force=true)
            rm(include_target; recursive=true, force=true)
        end
    end

    @testset "Local Mode Integration (# local)" begin
        tdir = mktempdir()
        try
            script = joinpath(tdir, "local_test.jl")
            write(
                script,
                """
  using QuickEnv # local, silent
  using Test
  """,
            )

            pkgs, fallback, excl, verbose, silent, create, desc, is_local = QuickEnv.parse_script_metadata(
                script
            )
            @test is_local == true

            QuickEnv.handle_matching_or_fallback(
                filter(p -> p != "QuickEnv", pkgs),
                fallback,
                excl,
                verbose,
                silent,
                is_local,
                script,
            )

            proj = Base.active_project()
            @test proj !== nothing
            @test dirname(proj) == tdir
        finally
            rm(tdir; recursive=true, force=true)
            Pkg.activate(; temp=true, io=devnull)
        end
    end

    @testset "Extract Included File Edge Cases" begin
        tdir = mktempdir()
        try
            helper = joinpath(tdir, "helper.jl")
            touch(helper)

            # 1. Valid relative path
            result = QuickEnv.extract_included_file("include(\"helper.jl\")", tdir)
            @test result == abspath(helper)

            # 2. Valid absolute path
            result_abs = QuickEnv.extract_included_file(
                "include(\"$(abspath(helper))\")", "/some/other/dir"
            )
            @test result_abs == abspath(helper)

            # 3. Non-existent file
            result_missing = QuickEnv.extract_included_file(
                "include(\"nonexistent.jl\")", tdir
            )
            @test result_missing == ""

            # 4. Dynamic include
            result_dynamic = QuickEnv.extract_included_file(
                "include(joinpath(@__DIR__, \"helper.jl\"))", tdir
            )
            @test result_dynamic == ""

            # 5. Line with trailing comment
            result_comment = QuickEnv.extract_included_file(
                "include(\"helper.jl\") # load helper", tdir
            )
            @test result_comment == abspath(helper)

            # 6. Non-include lines
            @test QuickEnv.extract_included_file("using Plots", tdir) == ""
            @test QuickEnv.extract_included_file("x = 42", tdir) == ""
        finally
            rm(tdir; recursive=true, force=true)
        end
    end

    @testset "Activate Matched Env Exact Boundary Check" begin
        mock_project_path = joinpath(
            DEPOT_PATH[1], "environments", "data_test", "Project.toml"
        )
        @test occursin("data", mock_project_path) == true
        @test basename(dirname(mock_project_path)) != "data"
    end

    @testset "Adversarial Parser Regressions" begin
        alias_script, io = mktemp()
        try
            write(io, "import DataFrames as DF\nusing CSV\nusing JSON: thing as J\nx = 1 # local\n")
            close(io)
            packages, _, _, _, _, _, _, is_local =
                QuickEnv.parse_script_metadata(alias_script)
            @test packages == ["DataFrames", "CSV", "JSON"]
            @test !is_local
        finally
            isopen(io) && close(io)
            rm(alias_script; force=true)
        end
        @test QuickEnv.extract_packages_from_line("") == String[]
        @test QuickEnv.extract_included_file("", pwd()) == ""
    end

    @testset "Cover Boundary Regressions" begin
        required64 = ["P$i" for i in 1:64]
        @test QuickEnv.find_minimal_covering_envs(
            required64, [("all", copy(required64))]
        ) == ["all"]
        @test isempty(QuickEnv.find_minimal_covering_envs(
            ["P$i" for i in 1:65], [("all", ["P$i" for i in 1:65])]
        ))
    end

    @testset "Malformed Cache Entries Fail Closed" begin
        cache = QuickEnv.load_cache()
        cache[QuickEnv.get_canonical_key(["MalformedCachePackage"])] = "not a table"
        malformed_script, malformed_io = mktemp()
        try
            close(malformed_io)
            cache["scripts"] = Dict(malformed_script => 17)
            QuickEnv.save_cache(cache)
            @test QuickEnv.check_cache_hit(["MalformedCachePackage"]) === nothing
            @test QuickEnv.check_script_cache_hit(malformed_script) === nothing
        finally
            isopen(malformed_io) && close(malformed_io)
            rm(malformed_script; force=true)
        end
    end

    @testset "Subprocess Activation Resilience" begin
        project_root = dirname(@__DIR__)
        separator = Sys.iswindows() ? ';' : ':'
        explicit_load_path = string(project_root, separator, "@stdlib")

        repeated_dir = mktempdir()
        try
            repeated_depot = joinpath(repeated_dir, "depot")
            mkpath(repeated_depot)
            write(joinpath(repeated_dir, "helper.jl"), "using QuickEnv\n")
            repeated_script = joinpath(repeated_dir, "main.jl")
            write(repeated_script, "using QuickEnv\ninclude(\"helper.jl\")\n")
            command = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no $repeated_script`
            process = run(
                setenv(
                    command,
                    "JULIA_DEPOT_PATH" => repeated_depot,
                    "JULIA_LOAD_PATH" => explicit_load_path,
                );
                wait=false,
            )
            @test success(process)

            isolated_process = run(
                setenv(
                    command,
                    "JULIA_DEPOT_PATH" => repeated_depot,
                    "JULIA_LOAD_PATH" => explicit_load_path,
                    "QUICKENV_ISOLATE_LOAD_PATH" => "true",
                );
                wait=false,
            )
            @test success(isolated_process)

            include_script = joinpath(repeated_dir, "included-main.jl")
            write(
                include_script,
                "using QuickEnv\nusing Dates\n" *
                "@assert startswith(basename(dirname(Base.active_project())), \"auto_\")\n",
            )
            include_command = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no -e 'include(ARGS[1])' $include_script`
            include_process = run(
                setenv(
                    include_command,
                    "JULIA_DEPOT_PATH" => repeated_depot,
                    "JULIA_LOAD_PATH" => explicit_load_path,
                );
                wait=false,
            )
            @test success(include_process)

            eval_command = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no -e 'before = Base.active_project(); using QuickEnv; @assert Base.active_project() == before'`
            eval_process = run(
                setenv(
                    eval_command,
                    "JULIA_DEPOT_PATH" => repeated_depot,
                    "JULIA_LOAD_PATH" => explicit_load_path,
                );
                wait=false,
            )
            @test success(eval_process)
        finally
            rm(repeated_dir; recursive=true, force=true)
        end

        if !Sys.iswindows()
            readonly_dir = mktempdir()
            readonly_depot = joinpath(readonly_dir, "depot")
            mkpath(readonly_depot)
            readonly_env = joinpath(readonly_depot, "environments", "readonly_target")
            mkpath(readonly_env)
            write(joinpath(readonly_env, "Project.toml"), "[deps]\n")
            write(
                joinpath(readonly_env, "Manifest.toml"),
                "julia_version = \"$(VERSION)\"\nmanifest_format = \"2.0\"\n[deps]\n",
            )
            readonly_script = joinpath(readonly_dir, "main.jl")
            write(
                readonly_script,
                "using QuickEnv # fallback: readonly_target, desc: read-only test\nusing Dates\n",
            )
            chmod(joinpath(readonly_env, "Project.toml"), 0o444)
            chmod(joinpath(readonly_env, "Manifest.toml"), 0o444)
            chmod(readonly_env, 0o555)
            chmod(dirname(readonly_env), 0o555)
            chmod(readonly_depot, 0o555)
            try
                depot_path = string(readonly_depot, separator, join(DEPOT_PATH, separator))
                command = `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no $readonly_script`
                process = run(
                    setenv(
                        command,
                        "JULIA_DEPOT_PATH" => depot_path,
                        "JULIA_LOAD_PATH" => explicit_load_path,
                    );
                    wait=false,
                )
                @test success(process)
            finally
                chmod(readonly_depot, 0o755)
                chmod(dirname(readonly_env), 0o755)
                chmod(readonly_env, 0o755)
                rm(readonly_dir; recursive=true, force=true)
            end
        end
    end

    @testset "Environment Selection Edge Cases" begin
        selection_depot = mktempdir()
        old_depot = copy(DEPOT_PATH)
        old_project = Base.active_project()
        try
            empty!(DEPOT_PATH)
            push!(DEPOT_PATH, selection_depot)
            env_root = joinpath(selection_depot, "environments")

            function write_selection_env(name, uuid; julia_version=string(VERSION))
                directory = joinpath(env_root, name)
                mkpath(directory)
                write(joinpath(directory, "Project.toml"), "[deps]\nFoo = \"$uuid\"\n")
                write(
                    joinpath(directory, "Manifest.toml"),
                    "julia_version = \"$julia_version\"\nmanifest_format = \"2.0\"\n" *
                    "[[deps.Foo]]\nuuid = \"$uuid\"\nversion = \"1.0.0\"\n",
                )
            end

            uuid_a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
            uuid_b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
            write_selection_env("older_minor", uuid_a; julia_version="1.10.0")
            write_selection_env("different_uuid", uuid_b)
            write_selection_env(".staging", uuid_a)

            @test !first(QuickEnv.check_manifest_compat(["older_minor"]))
            @test first(QuickEnv.check_manifest_compat(
                ["older_minor"]; require_current_julia=false
            ))
            @test !first(QuickEnv.check_manifest_compat([
                "older_minor", "different_uuid"
            ]; require_current_julia=false))
            @test !(".staging" in QuickEnv.find_matching_envs(["Foo"]))

            QuickEnv.handle_matching_or_fallback(
                ["Dates"], "stdlib_fallback", String[], false, true, false, ""
            )
            @test basename(dirname(Base.active_project())) == "stdlib_fallback"
        finally
            empty!(DEPOT_PATH)
            append!(DEPOT_PATH, old_depot)
            old_project !== nothing && Base.set_active_project(old_project)
            rm(selection_depot; recursive=true, force=true)
        end
    end
end
