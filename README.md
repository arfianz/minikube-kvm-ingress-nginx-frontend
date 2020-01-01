# Deploy a Frontend on Kubernetes

![kubernetes](kubernetes.png?raw=true)

[Kraken](https://kraken.octoperf.com/) is a [load testing](https://en.wikipedia.org/wiki/Load_testing) solution currently deployed on Docker. In order to use several injectors ([Gatling](https://en.wikipedia.org/wiki/Gatling_(software))) while running a load test, its next version might rely on Kubernetes.

	Kubernetes (commonly referred to as “K8s”) is an open source system that aims to provide a platform for automating the deployment, scalability and implementation of application containers on server clusters. It works with a variety of container technologies, and is often used with Docker. It was originally designed by Google and then offered to the Cloud Native Computing Foundation.

This blog post belongs to a series that describe how to use [Minikube](https://github.com/kubernetes/minikube), declarative configuration files and the **kubectl** command-line tool to deploy Docker micro-services on Kubernetes. It focuses on the installation of an **Angular 8 frontend application** served by an **NGinx Ingress controller**.

While being the most complex kind of [Kubernetes object management](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/), the declarative object configuration allows to apply and revert configuration updates. Also, configuration files can easily be shared or saved into a version control system like Git.

But before going to the **configuration of our frontend** and its **proxy**, let’s see what is needed **in order to follow this tutorial**.

## Prerequisites

Executing this blog post code and configuration samples on a local Linux machine requires:

- Kubernetes
- Minikube
- KVM or Virtualbox

### Install Kubernetes Command Line Client

First, we need to [install Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux). I used the version 1.16:

```bash
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.16.0/bin/linux/amd64/kubectl
$ chmod +x ./kubectl
$ sudo mv ./kubectl /usr/local/bin/kubectl
$ kubectl version -o json
```

The **kubectl version** command should display the 1.16 version.

### Install Minikube

You can deploy Kubernetes on your machine, but its preferable to do it in a VM when developing. It’s easier to restart from scratch if you made a mistake, or try several configurations without being impacted by remaining objects. **Minikube is the tool to test Kubernetes or develop locally**.

Download and [install Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/):

```bash
$ curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && chmod +x minikube
$ sudo install minikube /usr/local/bin
```

### KVM and Minikube driver

Minikube wraps Kubernetes in a Virtual Machine, so it needs an hypervisor: VirtualBox or KVM. Since I do my tests on a small [portable computer](https://octoperf.com/blog/2018/11/07/thinkpad-t440p-buyers-guide/), I prefer to use the lighter virtualization solution: KVM.

Follow this guide to install it on Ubuntu:

#### 1. Check that your CPU supports hardware virtualization

To run KVM, you need a processor that supports hardware virtualization. Intel and AMD both have developed extensions for their processors, deemed respectively Intel VT-x (code name Vanderpool) and AMD-V (code name Pacifica). To see if your processor supports one of these, you can review the output from this command: 
```bash
$ egrep -c '(vmx|svm)' /proc/cpuinfo
```
 - If **0** it means that your CPU doesn't support hardware virtualization.
 - If **1** or more it does - but you still need to make sure that virtualization is enabled in the BIOS.

You must see hvm flags in the output.

Alternatively, you may execute: 

```bash
$ kvm-ok 
```

which may provide an output like this: 

```bash
INFO: /dev/kvm exists
KVM acceleration can be used
```

If you see : 

```bash
INFO: Your CPU does not support KVM extensions
KVM acceleration can NOT be used
```

You can still run virtual machines, but it'll be much slower without the KVM extensions.

NOTE: You may see a message like "KVM acceleration can/can NOT be used". This is misleading and only means if KVM is *currently* available (i.e. "turned on"), *not* if it is supported. 


#### 2. Use a 64 bit kernel (if possible)

Running a 64 bit kernel on the host operating system is recommended but not required. 

- To serve more than 2GB of RAM for your VMs, you must use a 64-bit kernel (see 32bit_and_64bit). On a 32-bit kernel install, you'll be limited to 2GB RAM at maximum for a given VM.
- Also, a 64-bit system can host both 32-bit and 64-bit guests. A 32-bit system can only host 32-bit guests. 

To see if your processor is 64-bit, you can run this command: 

```bash
$ egrep -c ' lm ' /proc/cpuinfo
```

 - If **0** is printed, it means that your CPU is not 64-bit.
 - If **1** or higher, it is. Note: lm stands for Long Mode which equates to a 64-bit CPU.

Now see if your running kernel is 64-bit, just issue the following command:

```bash
$ uname -m
```

**x86_64** indicates a running 64-bit kernel. If you use see i386, i486, i586 or i686, you're running a 32-bit kernel.
Note: x86_64 is synonymous with amd64. 

#### 3. Installation of KVM

For the following setup, we will assume that you are deploying KVM on a server, and therefore do not have any X server on the machine.

You need to install a few packages first: 

```bash
$ sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
```

- **libvirt-bin** provides libvirtd which you need to administer qemu and kvm instances using libvirt
- **qemu-kvm** (kvm in Karmic and earlier) is the backend
- **ubuntu-vm-builder** powerful command line tool for building virtual machines
- **bridge-utils** provides a bridge from your network to the virtual machines 

You might also want to install virt-viewer, for viewing instances. 

#### 4. Add Users to Group

The group name is changed to libvirt:

```bash
$ sudo adduser `id -un` libvirt
$ Adding user '<username>' to group 'libvirt' ...
```

After this, you need to relogin so that your user becomes an effective member of the libvirtd group. The members of this group can run virtual machines. (You can also 'newgrp kvm' in a terminal, but this will affect only that terminal.) 

You need to ensure that your username is added to the groups: kvm and libvirtd.

To check: 

```bash
$ groups
adm dialout cdrom floppy audio dip video plugdev fuse lpadmin admin sambashare kvm libvirt
```

#### 5. Verify Installation

You can test if your install has been successful with the following command: 

```bash
$ virsh list --all
```

If on the other hand you get something like this: 

```bash
$ virsh list --all
libvir: Remote error : Permission denied
error: failed to connect to the hypervisor
```

Something is wrong (e.g. you did not relogin) and you probably want to fix this before you move on. The critical point here is whether or not you have write access to /var/run/libvirt/libvirt-sock.

The sock file should have permissions similar to: 

```bash
$ sudo ls -la /var/run/libvirt/libvirt-sock
srwxrwx--- 1 root libvirt 0 2010-08-24 14:54 /var/run/libvirt/libvirt-sock
```

Also, /dev/kvm needs to be in the right group. If you see: 

```bash
$ ls -l /dev/kvm
crw-rw----+ 1 root root 10, 232 Jul  8 22:04 /dev/kvm
```

You might experience problems when creating a virtual machine. Change the device's group to kvm/libvirtd instead: 

```bash
$ sudo chown root:libvirt /dev/kvm
```

Now you need to either relogin or restart the kernel modules: 

```bash
$ rmmod kvm
$ modprobe -a kvm
```

#### 6. Optional: Install virt-manager (graphical user interface)

If you are working on a desktop computer you might want to install a GUI tool to manage virtual machines. 

```bash
$ sudo apt install virt-manager
```

Virtual Machine Manager will appear in Applications -> System Tools menu. First create a new connection to local QEMU instance from File -> Add Connection menu. Localhost (QEMU) or QEMU/KVM should appear in the virtual machine list. Note: there already exist Localhost (QEMU Usermode) connection but this does not work at least on Ubuntu 10.04.


#### Finally [install the KVM driver](https://github.com/kubernetes/minikube/blob/master/docs/drivers.md#kvm2-driver):

```bash
$ curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2
$ chmod +x docker-machine-driver-kvm2
$ sudo mv docker-machine-driver-kvm2 /usr/local/bin/
```

Then, launch Minikube using the KVM2 driver:

```bash
$ minikube start --vm-driver=kvm2
😄  minikube v1.6.2 on Ubuntu 18.04
✨  Selecting 'kvm2' driver from user configuration (alternates: [virtualbox none])
💿  Downloading VM boot image ...
    > minikube-v1.6.0.iso.sha256: 65 B / 65 B [--------------] 100.00% ? p/s 0s
    > minikube-v1.6.0.iso: 150.93 MiB / 150.93 MiB [ 100.00% 1.01 MiB p/s 2m30s
🔥  Creating kvm2 VM (CPUs=2, Memory=2000MB, Disk=20000MB) ...
🐳  Preparing Kubernetes v1.17.0 on Docker '19.03.5' ...
💾  Downloading kubelet v1.17.0
💾  Downloading kubeadm v1.17.0
🚜  Pulling images ...
🚀  Launching Kubernetes ... 
⌛  Waiting for cluster to come online ...
🏄  Done! kubectl is now configured to use "minikube"
```

### K8S Definitions
Before continuing, it is best to define some concepts that are unique to Kubernetes.

![k8s](./k8s-cluster.png?raw=true)

- **A K8s cluster is divided** in [Nodes](https://kubernetes.io/docs/concepts/architecture/nodes/). A node is a worker machine and may be a VM or physical machine. In our case, the K8s cluster is composed of a single Node: the Minikube VM.
- When creating an application [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), **K8s creates one or several** [Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod/) on the available nodes. A Pod is a group of one or more Docker containers, with shared storage/network, and a specification for how to run the containers.
- **Theses Pods are regrouped** in [Services](https://kubernetes.io/docs/concepts/services-networking/service/). A Service defines a policy by which to access its targeted pods. For example: 
  - A service with the type NodePort exposes the Service on each Node’s IP at a static port. From outside the cluster, the service is accessible by requesting **<NodeIP>:<NodePort>**.
  - A LoadBalancer Service exposes the Service externally using the load-balancer of a cloud provider.

The NodePort solution would work for testing purposes but is not reliable in a production environment. And the LoadBalancer works only in the Cloud, not in a local test environment.

The solution that fits any use case is to install an Ingress Controller and use Ingress rules.

## TL; DR

Clone this repository.
It contains several K8s configuration files for Ingress and the Angular frontend.
It also contains a **Makefile**. Here is an extract of this file:

```bash
start:
	minikube start --vm-driver=kvm2 --extra-config=apiserver.service-node-port-range=1-30000
mount:
	minikube mount ${PWD}/grafana/config:/grafana
all:
	kubectl apply -R -f .
list:
	minikube service list
watch:
	kubectl get pods -A --watch
```

To launch the complete stack:
- Run **make start** to start Minikube (or copy paste the command above in a terminal if you do not have make on your computer),
- Execute **make all** to launch the Ingress controller and the Frontend,
- Wait for the various Pods to start (it may take some time to download the Docker images) using **make watch**,
- List the available services with **make list**.

```bash
|---------------|----------------------|--------------------------------|
|   NAMESPACE   |         NAME         |              URL               |
|---------------|----------------------|--------------------------------|
| default       | kubernetes           | No node port                   |
| ingress-nginx | ingress-nginx        | http://192.168.39.51:80        |
|               |                      | http://192.168.39.51:443       |
| kube-system   | kube-dns             | No node port                   |
| kube-system   | kubernetes-dashboard | No node port                   |
|---------------|----------------------|--------------------------------|
```

Open the URL of the **ingress-nginx** service with /administration appended: http://192.168.39.146:80/administration and check that the frontend is running and served by the NGINX proxy.

## Install and Configure NGinx Ingress

The concept of Ingress is split in two parts:
- The [Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/), it’s some kind of wrapper for an HTTP proxy,
- Ingress resources/rules that expose HTTP and HTTPS routes from outside the cluster to services within the cluster, depending on traffic rules.

### Motivation

In the current install of Kraken, we already use HAProxy to redirect the traffic to a specific Docker container. It’s the same principle here, except that you don’t configure the proxy directly but specify Ingress configuration objects. The proxy configuration is automatically updated for you by the controller.

**There is one issue with Ingress though, the configuration is done using annotation that are specific to the underlying controller**. So, unfortunately you cannot change the controller implementation without updating the Ingress resources.

The simpler Ingress controller is the one maintained by Kubernetes: Kubernetes NGinx, not to be confused with the one maintained by the NGINX team.

	Note: I also tried to use HAproxy’s Ingress Controller without success. I could not configure the URL Rewrite on this one.

Using a proxy and an Ingress controller allows us to serve multiple applications on the same hostname and port (80⁄443) but with different paths. For example, with Kakren we have:
- **/administration** for the administration frontend,
- **/gatling** for the load testing frontend,
- **/api/storage** for the file system storage backend,
- **/api/command** for the command execution backend,
- etc.

### Ingress Controller Installation

Let’s get our hands dirty and install an NGINX ingress controller.

We use the **kubectl apply** [command](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/#how-to-create-objects). It creates all resources defined in the given file. This file can be on the local file system or accessed using a URL.

	Note: Skip directly to the next chapter if you want to expose your Ingress Controller on port 80.

So, the first command to execute automatically installs all components required on the K8s cluster:

```bash
$ kubectl apply -f random/mandatory.yaml
namespace/ingress-nginx created
configmap/nginx-configuration created
configmap/tcp-services created
configmap/udp-services created
serviceaccount/nginx-ingress-serviceaccount created
clusterrole.rbac.authorization.k8s.io/nginx-ingress-clusterrole created
role.rbac.authorization.k8s.io/nginx-ingress-role created
rolebinding.rbac.authorization.k8s.io/nginx-ingress-role-nisa-binding created
clusterrolebinding.rbac.authorization.k8s.io/nginx-ingress-clusterrole-nisa-binding created
deployment.apps/nginx-ingress-controller created
limitrange/ingress-nginx created
```

All the related resources are deployed in a dedicated namespace called ingress-nginx. Check that the NGinx pod is started with the following command (press **CTRL + C** when the container status is Running):

```bash
$ kubectl get pods -n ingress-nginx --watch
NAME                                       READY   STATUS              RESTARTS   AGE
nginx-ingress-controller-9dfc54f55-hr4cp   0/1     ContainerCreating   0          20s
```

Our Ingress Controller is started, but not yet accessible externally from our K8s cluster. **We need to create a NodePort Service to expose it to the outside world**.

```bash
$ kubectl apply -f ingress/service-nodeport.yaml
service/ingress-nginx created
```

List all services in the ingress-nginx namespace:

```bash
$ kubectl get services -n ingress-nginx
NAME            TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)                     AGE
ingress-nginx   NodePort   10.96.133.33   <none>        80:7828/TCP,443:24516/TCP   21s
```

Here we see that the port 80 is dynamically mapped to the 32112 (you will most probably get a different mapping).

Listing all exposed services using Minikube confirms that the Ingress Controller is available:

```bash
$ minikube service list
|----------------------|---------------------------|--------------------------------|-----|
|      NAMESPACE       |           NAME            |          TARGET PORT           | URL |
|----------------------|---------------------------|--------------------------------|-----|
| default              | kubernetes                | No node port                   |     |
| ingress-nginx        | ingress-nginx             | http://192.168.39.51:7828      |     |
|                      |                           | http://192.168.39.51:24516     |     |
| kube-system          | kube-dns                  | No node port                   |     |
| kubernetes-dashboard | dashboard-metrics-scraper | No node port                   |     |
| kubernetes-dashboard | kubernetes-dashboard      | No node port                   |     |
|----------------------|---------------------------|--------------------------------|-----|
```

192.168.39.51 is the IP address allocated to our Minikube VM. You can also get it with the minikube ip command.

Open the URL http://192.168.39.51:7828 in a web browser, you will see a NGINX 404 page:

![404](./ingress-nginx-404.png?raw=true)

Our NGINX controller is responding!

### Expose NodePort 80

By default, Kubernetes is configured to expose NodePort services on the port range 30000 - 32767. But this port range can be configured, allowing us to use the port 80 for our Ingress Controller.

	Be warned though that this is discouraged.

Start by deleting our existing minikube VM with the command:

```bash
$ minikube delete
```

Then restart it with the option **apiserver.service-node-port-range=1-30000**:

```bash
$ minikube start --vm-driver=kvm2 --extra-config=apiserver.service-node-port-range=1-30000
😄  minikube v1.6.2 on Ubuntu 18.04
✨  Selecting 'kvm2' driver from user configuration (alternates: [virtualbox none])
💿  Downloading VM boot image ...
    > minikube-v1.6.0.iso.sha256: 65 B / 65 B [--------------] 100.00% ? p/s 0s
    > minikube-v1.6.0.iso: 150.93 MiB / 150.93 MiB [ 100.00% 1.01 MiB p/s 2m30s
🔥  Creating kvm2 VM (CPUs=2, Memory=2000MB, Disk=20000MB) ...
🐳  Preparing Kubernetes v1.17.0 on Docker '19.03.5' ...
    ▪ apiserver.service-node-port-range=1-30000
💾  Downloading kubelet v1.17.0
💾  Downloading kubeadm v1.17.0
🚜  Pulling images ...
🚀  Launching Kubernetes ... 
⌛  Waiting for cluster to come online ...
🏄  Done! kubectl is now configured to use "minikube"

```

Start the Ingress Controller and wait for it to start (kubectl get pods -n ingress-nginx --watch):

```bash
$ kubectl apply -f ingress/mandatory.yaml
```

Now that we can allocate the port 80, we also need to configure the NodePort service and expose the Ingress controller on this port. First download the configuration file:
And update it (**service-nodeport.yaml**), to add **nodePort: 80** for the http entry and **nodePort: 443** for the https one:

Apply the updated configuration:

```bash
$ kubectl apply -f ingress/service-nodeport.yaml 
```

Our Ingress Controller is now available on port 80 for HTTP and 443 for HTTPS:

```bash
$ minikube service list
|----------------------|---------------------------|--------------------------------|-----|
|      NAMESPACE       |           NAME            |          TARGET PORT           | URL |
|----------------------|---------------------------|--------------------------------|-----|
| default              | kubernetes                | No node port                   |     |
| ingress-nginx        | ingress-nginx             | http://192.168.39.51:80        |     |
|                      |                           | http://192.168.39.51:443       |     |
| kube-system          | kube-dns                  | No node port                   |     |
| kubernetes-dashboard | dashboard-metrics-scraper | No node port                   |     |
| kubernetes-dashboard | kubernetes-dashboard      | No node port                   |     |
|----------------------|---------------------------|--------------------------------|-----|
```

You may think “Why don’t we expose our frontend application directly using NodePort Service?”. That could also be done and it’s probably the simplest solution … for testing purpose. But it’s not manageable in a production environment with several frontend applications and backends running.

### Troubleshooting

Remember that you can list Pods with the command **kubectl get pods -n ingress-nginx --watch**.

- The **-n** parameter specifies the namespace, here ingress-nginx which is used by the NGinx Ingress controller,
- The **--watch** parameter refreshes the Pods list every time a modification occurs,
- Use the parameter **-A** to list resources for all namespaces.

In case your Pod is stuck with the status **CreatingContainer**, you can display a list of events that may let you know what is going on with the **describe** command:

```bash
$ kubectl describe pod nginx-ingress-controller-xxxxxxxx-yyyy -n ingress-nginx
```

Once a Pod is started, you can display the container logs with the command:

```bash
$ kubectl logs nginx-ingress-controller-xxxxxxxx-yyyy -n ingress-nginx
```

## Deploy an Angular 8 Frontend

### Angular8 Frontend Docker Image

We are about to use [Kraken’s administration](https://kraken.octoperf.com/administration/) Docker image: [octoperf/kraken-administration-ui](https://hub.docker.com/r/octoperf/kraken-administration-ui). Check out this blog post to know more about the creation of a Docker image for an Angular app: [Packaging Angular apps as docker images](https://octoperf.com/blog/2019/08/22/kraken-angular-workspace-multi-application-project/#packaging-angular-apps-as-docker-images).

You can also use your own Docker image. Be warned though that Kraken’s administration image is configured to use the specific BasePath **/administration**. We will need to configure an URL rewrite rule in our Ingress object. Check this chapter to know more about this: [How to serve multiple Angular app with HAProxy](https://octoperf.com/blog/2019/08/22/kraken-angular-workspace-multi-application-project/#how-to-serve-multiple-angular-applications-with-haproxy).

### How to Create a Deployment?

Start by applying the following configuration file, named **frontend-deployment.yaml**:

**A Kubernetes Deployment is responsible for starting Pods on available cluster Nodes**. Since our Pods contain a Docker container, the file above specifies the image, name and port mapping to use.

Apply the created configuration with the command:

```bash
$ kubectl apply -f frontend/frontend-deployment.yaml
```

Finally, check that the deployment has started one pod:

```bash
$ kubectl get deployments
```
Here we can see the **READY 1/1** column, it’s the number of Pods ready and the total that must be started.

### How to Expose a Deployment with a Service?

Like for the Deployment, applying configuration file and apply it. The configuration file is named **frontend-service.yaml**:

Apply it:

```bash
$ kubectl apply -f frontend/frontend-service.yaml 
```

There is no type and no nodePort defined in this service. We only use it to **regroup a logical set of Pods and make them accessible from inside the K8s cluster**.

```bash
$ kubectl get services
```

Here we can see that the **PORT(S)** column display only **80/TCP** for the frontend-service. Not the usual **80:30001/TCP** notation for an exposed port.

### How to Create an Ingress Object to Publicly Expose an App?

If not already done, you first need to have installed an Ingress Controller.

Then apply the following configuration file named **frontend-ingress.yaml**:

Ingress resources configuration is done using annotations:
- **ingress.class** should always be **"nginx"** unless you have [multiple Ingress Controllers running](https://kubernetes.github.io/ingress-nginx/user-guide/multiple-ingress/),
- **rewrite-target** is used to skip the **/administration** part or the URL when forwarding requests to the frontend Docker container ([URL Rewrite documentation](https://kubernetes.github.io/ingress-nginx/examples/rewrite/)),
- **proxy-read-timeout** sets a timeout for [SSE connections](https://stackoverflow.com/questions/21630509/server-sent-events-connection-timeout-on-node-js-via-nginx),
- **ssl-redirect** is used to deactivate Https redirection since we are not specifying a host: The default-server is called without any host, this server is configured with a self-signed certificate (Would display a big security warning in your browser).

Apply the configuration:

```bash
$ kubectl apply -f frontend/frontend-ingress.yaml 
```

And check that it is OK:

```bash
$ kubectl get ingresses
```

## Testing the Installation

If you configured your Ingress Controller to be exposed on port 80, the **minikube service list** will display a similar result:

```bash
$ minikube service list
|----------------------|---------------------------|--------------------------------|-----|
|      NAMESPACE       |           NAME            |          TARGET PORT           | URL |
|----------------------|---------------------------|--------------------------------|-----|
| default              | frontend-service          | No node port                   |     |
| default              | kubernetes                | No node port                   |     |
| ingress-nginx        | ingress-nginx             | http://192.168.39.51:80        |     |
|                      |                           | http://192.168.39.51:443       |     |
| kube-system          | kube-dns                  | No node port                   |     |
| kubernetes-dashboard | dashboard-metrics-scraper | No node port                   |     |
| kubernetes-dashboard | kubernetes-dashboard      | No node port                   |     |
|----------------------|---------------------------|--------------------------------|-----|
```

You can display the port mapping with the following command otherwise:

```bash
$ kubectl get services -n ingress-nginx
```

Opening this URL http://192.168.39.51:80/administration (the IP address is probably different for you) in your Web browser display the Kraken administration UI:

![administration](kraken-administration.png?raw=true)

## LICENSE


Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
