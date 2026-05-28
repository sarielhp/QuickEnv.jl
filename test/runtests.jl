using QuickEnv
using Test

@testset "QuickEnv.jl Tests" begin

    @testset "Script Metadata Parsing" begin
        # Write a mock Julia script with magic comments
        mock_script_content = """
        #! /bin/env julial
        # quickenv_fallback: plotting_test
        # quickenv_exclude: global, outdated_plotting, broken_env
        
        using QuickEnv
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
            pkgs, fallback, excluded = QuickEnv.parse_script_metadata(tmp_path)
            
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
        finally
            # Clean up the temp file
            rm(tmp_path)
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
        res4 = QuickEnv.filter_matching_envs(copy(mock_matching), "", ["broken_env", "plotting"])
        @test "v1.12" in res4
        @test "data" in res4
        @test !("broken_env" in res4)
        @test !("plotting" in res4)
    end

end
