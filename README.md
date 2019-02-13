# habitat-aspnet-eff

A demo ASP.Net IIS aplication using Entity Framework against a Sql Server database that can potentially be clustered.

## Setting up an Azure Demo Lab

### VM Povisioning

I provisioned manually. If you use terraform, then you are a better person than me and your tf templates would make a welcome PR!

**Domain Controller**

* Windows 2016 Standard DS1 v2 (1 vcpu, 3.5 GB memory)
* Enable Domain Controller Feature/role
* Create a "Forrest" using the wizard. Stick with the defaults and give it a name you will remember. I like "wrock.test".
* Reboot and make a note of the VM's private IP

**SQL Nodes**

* Create an Azure "Availability Set"
* Provision 2 Windows 2016 Standard E2s v3 (2 vcpus, 16 GB memory) and assign to the above availability set
* Name SQL1 and SQL2
* Go in to each VM's "Networking" settings in Azure and add the above domain controller's private IP to the "DNS Servers" of the VM's Network Interface
* RDP to each VM and join them to the domain you created and reboot.
* For all subsequent work you do on these nodes, make sure to login with the Domain Admin account (the one you used to log in to the DC).
* Create a folder called `backup` in the root of the `c:` drive.
* `Share` that `backup` folder. No need to add any special ACLs.
* On `SQL1` only, create a `c:\sqlserver` folder and placwe the install media of an Enterprise version of Sql Server 2016 or 2017 in that folder. Make sure that `c:\sqlserver\setup.exe` exists.
* Create a `c:\hab\svc\sqlserver\user.toml` with the following contents:

```
sa_password="Pass@word1"
port=8888
app_user="wrock\\admin$"
app_password=""
instance="hab_sql_server"
sys_admin_account="wrock\\mwrock"
svc_account="wrock\\mwrock"
svc_account_password="superSecret!!"
features="SQLEngine"
custom_install_media_dir="\\\\sql1\\c$\\sqlserver"
```

Note I used my `wrock` domain so you will need to swap that out with the domain name you created. And make sure the `svc_account` and `svc_account_password` are the domain anmin name and passord you are using. In the "real" world we don't need this to be a domain admin but it simplifies the lab setup for this demo.

* Create a `c:\hab\svc\sqlserver-ha-ag\user.toml` with the following contents:

```
endpoint_port=5022
probe_port=59999
availability_group_name="AG"
availability_group_ip="10.0.1.111"
availability_group_failover_threshold=1000
backup_path="\\\\$env:computername\\backup"
databases="'ContosoUniversity2'"
cluster_name="sql"
cluster_ip="10.0.1.110"
```

Note that the 2 IPs above should be in your private subnet and unassigned to any VM. It does not matter what they are exactly. Make a note of the `availability_group_ip` which you will need for creating the Azure Load Balancer.

**Admin/IIS Node**

* Windows 2016 Standard DS1 v2 (1 vcpu, 3.5 GB memory)
* Name ADMIN
* Go in the each VM's "Networking" settings in Azure and add the above domain controller's private IP to the "DNS Servers" of the VM's Network Interface
* RDP to each VM and join them to the domain you created and reboot.
* For all subsequent work you do on these nodes, make sure to login with the Domain Admin account (the one you used to log in to the DC).

### Creating an Azure Load Balancer

* Create an Azure Load Balancer in the resource group of the above VMs
* Add a Front End IP configuration assigned to the `availability_group_ip` used above.
* Add a Backend Pool that is bound to the Availability Set created above and add the 2 SQL nodes
* Add a Health Probe with `TCP` port `59999` (the same one in `probe_port` above). Stick with the defaults for the other values.
* Add a Load Balancing Rule bound to the above Frontend, pool and probe. Set the backend port to `8888` the same port from the `port` in the `sqlserver` `user.toml`.

### Initial Hab installation and setup

These steps should be followed for SQL1, SQL2 and ADMIN.

* Install Chocolatey with `Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))`
* Install the hab cli with `choco install habitat -y`
* Enable Firewall rules to allow the supervisors to talk to eachother:

```
New-NetFirewallRule -DisplayName "Habitat TCP" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9631,9638
New-NetFirewallRule -DisplayName "Habitat UDP" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 9638
```

### Running the Habitat Supervisor as a Windows Service on SQL1 and SQL2

This is not crucial but it will come in extremely handy if you want to watch the supervisor output from sql1 and sql2 on your admin VM so you don't have to jump around to different RDP sessions. Because the clustering configuration that Habitat does cannot run over winrm, you cannot start the supervisor of sql1 and sql2 from a remote console. Instead, you can run the supervisor locally as a service and then simply stream the supervisor log from a remote console.

Follow these steps on SQL1 and SQL2:

* run:
```
hab pkg install core/windows-service
hab pkg exec core/windows-service install
```

* Edit `C:\hab\svc\windows-service\HabService.exe.config` and change:

```
<add key="launcherArgs" value="--no-color" />
```

to

```
<add key="launcherArgs" value="--no-color --peer 10.0.1.11" />
```

The `peer` IP you use should be the IP address of sql1.

* Edit the properties of the `Habitat` windows service and change the `Log On` to you domain admin account.
* Start the Habitat service

Habitat supervisor logs will go to `C:\hab\svc\windows-service\logs\Habitat.log`

### Sql Server Management Studio on ADMIN

Assuming you have already installed the hab cli and enabled the firewall on `admin`, the only thing left to setup here is Sql Server Management Studio which is the Sql Server GUI administration tool. This makes it easy to see and show what is going on with your sql nodes.

You have already installed Chocolatey so run:

```
choco install sql-server-management-studio -y
```

### Start the SQL Server services

It is going to be easiest to manage all hab interaction from one VM. The `admin` vm is probably best. I like to use 2 desktops on the admin VM. On the first desktop I run Sql Server Management Studio and a browser where I run the .Net app. On the second I arrange 6 powershell consoles for viewing and interacting with the supervisors.

* Open 6 powershell consoles and size them so you have 2 columns and 3 rows.
* Int the top left console run:

```
enter-pssession sql1
Get-Content C:\hab\svc\windows-service\logs\Habitat.log -Wait
```

* Run the same in the middle left console except you will enter a `pssession` on `sql2`
* In the right top and middle consoles, `enter-pssession sql1` and `enter-pssession sql2` respectively.
* In both right consoles run `hab svc start core/sqlserver`

You should now begin to see some activity in the supervisor output in the left consoles. Since this is the first time starting `sqlserver` it will run through its installer. This can take several minutes so you will expect a very long pause (perhaps 10 minutes).

### Start the .net application

In the lower left console you will start a local supervisor (peered to the sql servers) running the .net app:

```
$env:HAB_FEAT_INSTALL_HOOK=$true
hab svc start mwrock/ContosoUniversity --peer 10.0.1.4 --bind database:sqlserver.default
```

The peer IP should be the private IP of either `sql1` or `sql2`.

The first time you start the .net app, it will install and configure IIS. This can take a few minutes so expect some "silence" as the supervisor initializes the service.

### Connecting SSMS to Sql Nodes

You will now want to connect Sql Server Management Studio (SSMS) to `sql1` and `sql2`. Create 2 Database Engine connections to `SQL1\HAB_SQL_SERVER` and `SQL2\HAB_SQL_SERVER`.

### Hitting .net app in Browser and Creating DB

Open a browser to `http://localhost:8099/hab_app/Student`. This may take several seconds to load. Once it has loaded, you should see a database in SSMS on one of the sql nodes.

### Clustering the Sql Servers

In both the right top and middle consoles (`sql1` and `sql2`) run:

```
hab svc start core/sqlserver-ha-ag --bind database:sqlserver.default
```

This will run for several seconds and once both left side supervisor consoles say `Availability group configuration complete!` you can validate the cluster by "refreshing" the databases in both sql nodes in SSMS. Now both nodes should have a `contosouniversity2` database marked `(Synchronized)`.

### Stop the .Net app and Restart it Bound to the Cluster

In the lower right console, run:

```
hab svc stop mwrock/ContosoUniversity
hab svc start mwrock/ContosoUniversity --bind database:sqlserver.default cluster:sqlserver-ha-ag.default
```

Now a look at the .net `web.config` file should show that the connection string is pointing to the cluster and not an individual IP:

```
cat C:\hab\svc\ContosoUniversity\config\Web.config -TotalCount 14
```

### Validate that Killing the Primary SQL Node Auto Fails to the Secondary

Determine which SQL node in the primary node by expanding in SSMS `Always On High Availability`/`Availability Groups`. This will show the availability group as marked either `(Primary)` or `(Secondary)`. In the console for that primary sql node run:

```
hab svc stop core/sqlserver
```

Now refresh the `Secondary` availability group in SSMS and it should change to `Primary`. Also refresh the browser and ensure the app is continuing to work.

I have seen episodes where the very first refresh raises a netwok error but refreshing again reveals success. I'm honestly not sure what the workaround of that error is.

### Cleaning up to Demo Again

You may want to demo this several times without running though all the setup again. In fact you may not ever want to publicly demo this first run and have an audience wait for the sql installs and IIS setup. The subsequent runs will go much faster because the base features are setup.

I like to simply clearout the availability group settings and the failover cluster.

* Stop the .net hab service and the `sqlserver-ha-ag` services on the sql nodes
* In SSMS delete the availability group (you only need to do this on one of the nodes) and delete the `contosouniversity2` database on both sql nodes
* In one of the sql consoles un:

```
disable-SqlAlwaysOn -Path SQLSERVER:\SQL\sql1\hab_sql_server -NoServiceRestart
disable-SqlAlwaysOn -Path SQLSERVER:\SQL\sql2\hab_sql_server -NoServiceRestart
```

* Stop `core/sqlserver` and then start it on both nodes
* RDP to `sql1` or `sql2` (can't do this via winrm) and run `Remove-Cluster sql1 -CleanupAD -Force` - you only have to run this on one of the sql nodes
* RDP to the domain controller and open the Active Directory Users and Computers admin tool. Select the `Computers` node under your domain and delete the `ag` computer
