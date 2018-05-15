$pkg_name="ContosoUniversity"
$pkg_origin="mwrock"
$pkg_version="0.2.0"
$pkg_maintainer="Matt Wrock"
$pkg_license=@('MIT')
$pkg_description="A sample ASP.NET Full EFF IIS app"
$pkg_deps=@("core/dsc-core")
$pkg_build_deps=@("core/nuget")
$pkg_source="https://code.msdn.microsoft.com/ASPNET-MVC-Application-b01a9fe8/file/169473/2/ASP.NET%20MVC%20Application%20Using%20Entity%20Framework%20Code%20First.zip"
$pkg_shasum="2259f86eb89fc921ce8481fc3297f3836815f4e2b3cab1f7353f799ec58ed2ef"

$pkg_exports=@{
    "port"="port"
}

$pkg_binds=@{
  "database"="username password port"
}
$pkg_binds_optional=@{
  "cluster"="name"
}

function Invoke-Build {
  nuget restore "C#/$pkg_name/packages.config" -PackagesDirectory "$HAB_CACHE_SRC_PATH/$pkg_dirname/C#/packages" -Source "https://www.nuget.org/api/v2"
  nuget install MSBuild.Microsoft.VisualStudio.Web.targets -Version 14.0.0.3 -OutputDirectory $HAB_CACHE_SRC_PATH/$pkg_dirname/
  $env:VSToolsPath = "$HAB_CACHE_SRC_PATH/$pkg_dirname/MSBuild.Microsoft.VisualStudio.Web.targets.14.0.0.3/tools/VSToolsPath"
  ."$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe" "C#/$pkg_name/${pkg_name}.csproj" /t:Build /p:VisualStudioVersion=14.0
  if($LASTEXITCODE -ne 0) {
      Write-Error "dotnet build failed!"
  }
}

function Invoke-Install {
  ."$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe" "C#/$pkg_name/${pkg_name}.csproj" /t:WebPublish /p:WebPublishMethod=FileSystem /p:publishUrl=$pkg_prefix/www
  Remove-Item $pkg_prefix/www/Web.config
}
