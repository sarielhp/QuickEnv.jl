using QuickEnv
using Test

@testset "QuickEnv.jl Tests" begin
    @testset "Script Metadata Parsing" begin
        # Write a mock Julia script with magic comments (inline)
        mock_script_content = """
        #!/usr/bin/env julia

        using QuickEnv # fallback: plotting_test, exclude: global, outdated_plotting, broken_env, silent, create: data_test, description: "Inline test description"
        using Plots
        import DataFrames: DataFrame

        # Some comments that shouldn't impact parsing:
        # using NotAPackage
        # import AlsoNotAPackage
        """

        # Create a temporary file
        tmp_path, io = mktemp()
        try
            write(io, mock_script_content)
            close(io)

            # Parse the metadata
            pkgs, fallback, excluded, is_silent, create_env, description = QuickEnv.parse_script_metadata(
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
        finally
            # Clean up the temp file
            rm(tmp_path)
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

            _, _, _, _, create_env_s, _ = QuickEnv.parse_script_metadata(tmp_path_s)
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

            _, _, _, _, _, description_d = QuickEnv.parse_script_metadata(tmp_path_d)
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

            _, _, _, _, _, description_d2 = QuickEnv.parse_script_metadata(tmp_path_d2)
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

            _, _, _, _, _, description_d3 = QuickEnv.parse_script_metadata(tmp_path_d3)
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

            _, fallback_env_f, _, _, _, description_f = QuickEnv.parse_script_metadata(tmp_path_f)
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

            _, _, _, _, create_env_c, description_c = QuickEnv.parse_script_metadata(tmp_path_c)
            @test create_env_c == "data_test"
            @test description_c == "Create desc test"
        finally
            rm(tmp_path_c)
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

        # 1. Standard Case: No fallback, no exclusions
        res1 = QuickEnv.filter_matching_envs(copy(mock_matching), "", String[])
        @test res1 == ["v1.12", "plotting", "data", "broken_env"]

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
        @test "v1.12" in res4
        @test "data" in res4
        @test !("broken_env" in res4)
        @test !("plotting" in res4)
    end
end
