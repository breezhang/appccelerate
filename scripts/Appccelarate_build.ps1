
Properties {
  $projectName ="Appccelerate"
  
  $base_dir = Resolve-Path ..
  $binaries_dir = "$base_dir\binaries"
  $publish_dir = "$base_dir\publish"
  $source_dir = "$base_dir\source"
  
  $sln_file = "$source_dir\$projectName.sln"
  
  $version_file_name = "Version.txt"
  $dependencies_file_name = "Dependencies.txt"
  $assembly_info_file_name = "VersionInfo.g.cs"
  
  $xunit_runner = "$source_dir\packages\xunit.runners.1.9.1\tools\xunit.console.clr4.x86.exe"
  $mspec_runner = "$source_dir\packages\Machine.Specifications.0.5.8\tools\mspec-clr4.exe"
  
  $publish = $false
  $parallelBuild = $true
  
  $build_config = "Release"
  $build_number = 0
}

FormatTaskName (("-"*70) + [Environment]::NewLine + "[{0}]"  + [Environment]::NewLine + ("-"*70))

Task default –depends Clean, WriteAssemblyInfo, Build, Test, CopyBinaries, ResetAssemblyInfo, Nuget

Task Clean { 
    #Delete all bin and obj folders within source directory
    Get-Childitem $source_dir -Recurse | 
    Where {$_.psIsContainer -eq $true -and ($_.name -eq "bin" -or $_.name -eq "obj") } | 
    Foreach-Object { 
        Write-Host "deleting" $_.fullname
        Remove-Item $_.fullname -force -recurse -ErrorAction SilentlyContinue
    }
    
    Remove-Item $publish_dir -force -recurse -ErrorAction SilentlyContinue
    Remove-Item $binaries_dir -force -recurse -ErrorAction SilentlyContinue
}

Task WriteAssemblyInfo -precondition { return $publish } -depends clean{
    $assemblyVersionPattern = 'AssemblyVersionAttribute\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
	$fileVersionPattern = 'AssemblyFileVersionAttribute\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
    
    Get-CoreProjects | 
    Foreach-Object { 
       $versionFile = $_.fullname + "\" + $version_file_name
       $assemblyInfoFile = $_.fullname + "\Properties\" + $assembly_info_file_name
       $version = (Get-Content $versionFile)
       $assemblyVersion = 'AssemblyVersionAttribute("' + $version + '.0.0' + '")';
       $fileVersion = 'AssemblyFileVersionAttribute("' + $version + '.'+ $build_number +'.0' + '")';
	
    	(Get-Content $assemblyInfoFile) | ForEach-Object {
    		% {$_ -replace $assemblyVersionPattern, $assemblyVersion } |
    		% {$_ -replace $fileVersionPattern, $fileVersion }
    	} | Set-Content $assemblyInfoFile
        
    }
}

Task Build -depends Clean, WriteAssemblyInfo {
    Write-Host "building" $sln_file 
    if($parallelBuild){
    
        if($Env:MAX_CPU_COUNT){
            $maxcpucount = ":$Env:MAX_CPU_COUNT"
        }

        Exec { msbuild $sln_file "/p:Configuration=$build_config" "/p:Platform=Any CPU" "/verbosity:minimal" "/fileLogger" "/fileLoggerParameters:LogFile=$base_dir/msbuild.log" "/m$maxcpucount" }
    }else{
        Exec { msbuild $sln_file "/p:Configuration=$build_config" "/p:Platform=Any CPU" "/verbosity:minimal" "/fileLogger" "/fileLoggerParameters:LogFile=$base_dir/msbuild.log" }
    }
}

Task Test -depends Clean, Build {
    RunUnitTest
    RunMSpecTest
}

Task CopyBinaries -precondition { return $publish } { #-depends Clean, WriteAssemblyInfo, Build, Test {
    #create binaries dir
    Write-Host "create binaries directory"
    New-Item $binaries_dir -type directory -force
    
    #copy core binaries
    Get-CoreProjects |  
    Foreach-Object { 
        $project = $_.fullname
        $projectBinaries = $project + "\bin\$build_config\" 
        $projectName = $_.name
        $dependencies_file = $project +"\"+ $dependencies_file_name
        
        Get-Childitem $projectBinaries -Recurse | 
        Where{
            $_.name -eq "$projectName.dll" -or 
            $_.name -eq "$projectName.xml" -or
            $_.name -eq "$projectName.pdb" } |
        Foreach-Object {
            $endpath = $_.fullname.Replace($projectBinaries, "").Replace($_.name, "")
            $destination = $binaries_dir+"\"+$build_config+"\"+$projectName+"\"+$endpath
            Write-Host "copy" $_.fullname "to" $destination
            if (!(Test-Path -path $destination)) {New-Item $destination -Type Directory}
            Copy-Item $_.fullname $destination -force
        }
        
         #copy additionall binaries
         if(Test-Path $dependencies_file){
            (Get-Content $dependencies_file) | ForEach-Object {
                $name = $_
        		Get-Childitem $projectBinaries -Recurse |
                 Where{ $_.name -like $name } |
                Foreach-Object {
                    $endpath = $_.fullname.Replace($projectBinaries, "").Replace($_.name, "")
                    $destination = $binaries_dir+"\"+$build_config+"\"+$projectName+"\"+$endpath
                    Write-Host "copy" $_.fullname "to" $destination 
                    if (!(Test-Path -path $destination)) {New-Item $destination -Type Directory}
                    Copy-Item $_.fullname $destination -force
                }
        	}
         }
    }

}

Task ResetAssemblyInfo -precondition { return $publish } { #-depends Clean, WriteAssemblyInfo, Build, Test, CopyBinaries {
    Write-Host "reseting assembly info"
}

Task Nuget -precondition { return $publish } { #-depends Clean, WriteAssemblyInfo, Build, Test, CopyBinaries {
    Write-Host "reseting assembly info"
}

Function RunUnitTest(){
    $bin_folders = Get-Childitem $source_dir -include bin -Recurse
    $test_assemblies = Get-Childitem $bin_folders -include *Test.dll -Recurse 
    if($test_assemblies -ne $null){
        foreach ($test_assembly in $test_assemblies)
        {
            Write-Host "testing" $test_assembly
            exec { cmd /c "$xunit_runner $test_assembly" }
        }
    }
}

Function RunMSpecTest(){
    $bin_folders = Get-Childitem $source_dir -include bin -Recurse
    $test_assemblies = Get-Childitem $bin_folders -include *Specification.dll -Recurse 
    if($test_assemblies -ne $null){
        foreach ($test_assembly in $test_assemblies)
        {
            Write-Host "testing" $test_assembly
            exec { cmd /c "$mspec_runner $test_assembly" }
        }
    }
}

Function Get-CoreProjects(){
    return Get-Childitem $source_dir | 
    Where{$_.psIsContainer -eq $true `
    -and $_.name -like "$projectName.*" `
    -and $_.name -notlike "$projectName.*.Test" `
    -and $_.name -notlike "$projectName.*.Specification" `
    -and $_.name -notlike "$projectName.*.Sample" `
    -and $_.name -notlike "$projectName.*.Performance" `
    -and $_.name -notlike "\.*"}
}