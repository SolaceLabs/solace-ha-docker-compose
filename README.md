Configure High-availability Groups Using Docker Compose
=====
This project provides instructions and tools to use Docker Compose to configure an HA redundancy group of Solace PubSub+ software message broker Docker containers. 
<br><br>
## Before you begin
In sample configuration below, we will use a Docker Compose template to set up an HA group. This sample configuration, which uses Solace PubSub+ Standard, is suitable for demonstrating and testing PubSub+ fundamentals, such as HA failover and guaranteed messaging, in non-production situations. The intent of the configuration is to help you become familiar with the ins-and-outs of HA set up as a step towards using more advanced, production-oriented configurations. 


### What you will need

* If you are using macOS:
  * Mac OS X Yosemite 10.10.3 or higher.
* If you are using Windows:
  * Windows Pro 10.
  * Windows PowerShell.
* Docker installed, with at least 6 GiB of memory (4 GiB must be RAM) and 2 virtual cores dedicated to Docker. For this example, 4 GiB of RAM, 2 GiB of swap space, and 2 virtual cores have been dedicated to Docker for Mac. To learn about allocating memory and swap space, refer to the Docker Settings page for [Docker for Mac](https://docs.docker.com/docker-for-mac/#advanced) or [Docker for Windows](https://docs.docker.com/docker-for-windows/#advanced).
* A host machine with 8 GB RAM and 4 CPU cores with hyper-threading enabled (8 virtual cores) is recommended.
* All software message broker Docker container images in the HA group must be the same: Solace PubSub+ 8.10 or higher.


### Docker Compose
The Docker Compose template allows you to get an HA group up-and-running using a single command. Once the command is executed, the template automatically creates all the necessary containers and configures the HA group. It also creates a load balancer, HAProxy, to check the health of the primary and backup message brokers. The load balancer monitors the health of the primary and standby message brokers, and based on the results of the health check, directs traffic to the active message broker. The diagram below illustrates the HA group setup fronted by a load balancer.

![](images/LoadBalancer_HATriplet.png)

The template contains the following two files:
* PubSub_standard_HA.yml — The docker-compose script that creates the containers for the primary, backup, and monitoring nodes as well as a container for the load balancer. The script also contains configuration keys for setting up redundancy, which automatically get the HA group up-and-running.
* _assertMaster.perl_ — A Perl script that creates the HAProxy load balancer configuration file, which is mapped to the load balancer container. Once the containers are created, the load balancer automatically executes the **Assert master admin operation**, which ensures that the configuration of the primary and backup message brokers are synchronized. For more information, refer to [Solace PubSub+ documentation - Asserting Message Broker System Configurations](https://docs.solace.com/Configuring-and-Managing-Routers/Using-Config-Sync.htm#Assertin).


### Limitations
* The following features are not supported: Replication, Docker Engine Swarm mode.
* Multi-Node Routing (MNR) is not supported at the 100 connection scaling tier. To use MNR, you must use the 1,000 connection scaling tier or higher.
* Only bridge networking is supported.
<br><br>
## Step 1: Get a Software Message Broker 

First, you need to obtain a message broker Docker package, which is a compressed tar archive containing a message broker Docker repository consisting of a single  message broker Docker image. 

**Solace PubSub+ Standard**: Go to [dev.solace.com/downloads](http://dev.solace.com/downloads/#vmr). Then select the Docker tile and choose  Standard. After you read and acknowledge the license agreement, an email will be sent to you with a download link to a compressed archive file called `solace-pubsub-standard-<version>-docker.tar.gz`.

**Solace PubSub+ Enterprise Evaluation Edition**: Go to the Downloads page of dev.solace.com. Then select the Docker tile and choose Enterprise Evaluation Edition. After you read and acknowledge the license agreement, an email will be sent to you with a download link to a compressed archive file called `solace-pubsub-evaluation-<version>-docker.tar.gz`.

**Solace PubSub+ Enterprise**: If you have purchased a Docker image of Solace PubSub+ Enterprise, Solace will give you information for how to download the compressed tar archive package from a secure Solace server. Contact [Solace Support](https://solace.com/support) if you require assistance.

Once you have obtained a copy of the message broker package, you can upload it to a directory on your host and load the image using these two steps:
1. Start Docker and open a terminal (PowerShell for Windows). 
2. Load the image:
<pre>
> docker load -i Users/username/Downloads/solace-pubsub-standard-8.10.x.x-docker.tar
</pre>

In this example,  the compressed tar archive of Solace PubSub+ Standard has been uploaded to `Users/username/Downloads` directory. When loading is finished, you can check the image with the `docker images` command.
<br><br>
## Step 2: Download Docker Compose Template

Clone the GitHub repository containing the Docker Compose template.
<pre>
> git clone https://github.com/SolaceDev/ha-quickstart-docker-compose
> cd ha-quickstart-docker-compose
</pre>
Alternatively, you can also download the Zip file through the clone or download tab. 
<br><br>
## Step 3: Run Docker Compose

Before running the docker-compose command, it's recommended that you execute docker volume prune to remove unused local volumes. This is recommended if you are setting up an HA group in a resource-limited environment such as a laptop with limited disk space.

Run the following command to get the HA group up-and-running.

<pre>
> $env:TAG="<docker-image-tag>"; $env:ADMIN_PASSWORD="admin"; docker-compose -f PubSub_Standard_HA.yml up
</pre>

Where: `<docker-image-tag>` is the TAG number of the software message broker Docker image. You can check the TAG number using the docker images command.

Once the primary, backup, monitoring, and lb (load balancer) containers are created, it will take about 60 seconds for the message brokers to come up and the Assert master admin operation to complete. You will notice the following behaviour on the terminal:
<pre>
...
primary     |
lb          |  checking if message broker 127.0.0.1:8080 is ready, attempt # 5
lb          |  checking if message broker 127.0.0.1:8080 is ready, attempt # 6
lb          |  checking if message broker 127.0.0.1:8080 is ready, attempt # 7
lb          |  checking if message broker 127.0.0.1:8080 is ready, attempt # 8
lb          |  checking if message broker 127.0.0.1:8080 is ready, attempt # 9
lb          |  checking if message broker 127.0.0.1:8080 is ready, attempt # 10
lb          |  Assert master admin operation completed, attempt # 10
</pre>

The HA group will be up-and-running once the **Assert master admin operation** is completed. You can check the status of the containers by executing the `docker ps` command. The status of all the four containers, primary, backup, monitoring, and lb, must be Up.
<br><br>
## Step 4: Manage the Container
You can access the Solace management tool, WebUI, or the Solace CLI to start issuing configuration or monitoring commands on the message broker.

Solace WebUI management access:

1. Open a browser and enter this url: http://localhost:8080
2. Log in as user `admin` with password `admin`.

Solace CLI management access:

1. Enter the following docker exec command to access the Solace CLI on the primary message broker:

<pre>
> docker exec -it primary /usr/sw/loads/currentload/bin/cli -A
</pre>
2. Enter the following commands to enter configuration mode:
<pre>
primary> enable
primar# config
primary(configure)#
</pre>
3. Issue configuration or monitoring commands. For a list of commands currently supported on the message broker, refer to [Solace Documentation - Solace CLI](http://192.168.1.192/home/public/RND/Docs/Cust_Doc_Bug_Fixes/Solace-CLI/Using-Solace-CLI.htm).
<br><br>
## Next Steps
At this point you have an HA redundancy group running on your platform and Guaranteed Messaging is enabled. You can now do things like use the SDKPerf tool to test messaging, perform administrative task using WebUI, or test the HA group’s failover operation.

* [Download SDKPerf] — To get started, see SDKPerf's Quick Start guide.
* [Validate Failover] — Learn to validate the HA group’s failover operation
* [WebUI] — Use the Solace WebUI to administer the HA group.
