Configuration NewWebsite
{
    Import-DscResource -Module xWebAdministration
    Node 'localhost' {
        WindowsFeature ASP 
        { 
            Ensure = "Present"
            Name = "Web-Asp-Net45"
        }

        xWebAppPool {{cfg.app_pool}}
        {
            Name   = "{{cfg.app_pool}}"
            Ensure = "Present"
            State  = "Started"
        }
        
        xWebsite {{cfg.site_name}}
        {
            Ensure          = "Present"
            Name            = "{{cfg.site_name}}"
            State           = "Started"
            PhysicalPath    = Resolve-Path "{{pkg.svc_path}}"
            ApplicationPool = "{{cfg.app_pool}}"
            BindingInfo = @(
                MSFT_xWebBindingInformation
                {
                    Protocol = "http"
                    Port = {{cfg.port}}
                }
            )
        }

        xWebApplication {{cfg.app_name}}
        {
            Name = "{{cfg.app_name}}"
            Website = "{{cfg.site_name}}"
            WebAppPool =  "{{cfg.app_pool}}"
            PhysicalPath = Resolve-Path "{{pkg.svc_var_path}}"
            Ensure = "Present"
        }
    }
}
