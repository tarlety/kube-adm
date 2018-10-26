#!/bin/bash

[[ "$SSHPORT" == "" ]] && SSHPORT=22
[[ "${SECRET}" == "" ]] && SECRET=~/.secret
echo SECRET=${SECRET} SSHPORT=$SSHPORT

case $1 in
	"preflight")
		# ref: https://kubernetes.io/docs/setup/independent/install-kubeadm/
		# required to execute this on node
		shift
		HOST=$1
		USER=$2
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo apt update -y"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo apt install -y apt-transport-https curl"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} 'echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list'
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo apt update -y"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo apt install -y kubelet kubeadm kubectl"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo apt-mark hold kubelet kubeadm kubectl"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo swapoff -a"
		;;
	"init")
		shift
		MASTER=$1
		USER=$2
		NETWORK=$3
		mkdir -p ${SECRET}/.kube
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "sudo kubeadm init --pod-network-cidr ${NETWORK} 2>&1" | tee ${SECRET}/.kube/init
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "mkdir -p \$HOME/.kube"
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "sudo cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config"
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
		;;
	"join")
		shift
		HOST=$1
		USER=$2
		JOINCMD=`cat ${SECRET}/.kube/init | grep "kubeadm join" | sed 's/^ *//'`
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo ${JOINCMD}"
		;;
	"cni")
		shift
		MASTER=$1
		USER=$2
		# https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/flannel
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/canal/rbac.yaml"
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/canal/canal.yaml"
		;;
	"leave")
		shift
		MASTER=$1
		USER=$2
		HOST=$3
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "kubectl drain $HOST --delete-local-data --force --ignore-daemonsets"
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "kubectl delete node $HOST"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo kubeadm reset -f"
		;;
	"status")
		shift
		MASTER=$1
		USER=$2
		echo "## nodes"
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "kubectl get nodes"
		echo "## pods"
		ssh -t ${USER}@${MASTER} -p ${SSHPORT} "kubectl get pods --all-namespaces"
		echo "## cni"
		;;
	"master-network-up")
		shift
		USER=$1
		shift
		HOSTS=$*
		SECRET=${SECRET} $0 master-network-down $USER $HOSTS
		for HOST in $HOSTS
		do
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo iptables -I INPUT -p tcp -s 10.32.0.0/12 -j ACCEPT"
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "for HOST in $HOSTS ; do sudo iptables -I INPUT -m multiport -p tcp -s \$HOST --dport 6443,2379:2380,10250:10252,6783 -j ACCEPT ; sudo iptables -I INPUT -m multiport -p tcp -s \$HOST --sport 6443,2379:2380,10250:10252,6783 -j ACCEPT ; sudo iptables -I INPUT -m multiport -p udp -s \$HOST --dport 6783,6784 -j ACCEPT ; done ; sudo iptables-save | sudo tee /etc/iptables/rules.v4"
		done
		;;
	"master-network-down")
		shift
		USER=$1
		shift
		HOSTS=$*
		for HOST in $HOSTS
		do
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo iptables -D INPUT -p tcp -s 10.32.0.0/12 -j ACCEPT"
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "for HOST in $HOSTS ; do sudo iptables -D INPUT -m multiport -p tcp -s \$HOST --dport 6443,2379:2380,10250:10252,6783 -j ACCEPT ; sudo iptables -D INPUT -m multiport -p tcp -s \$HOST --sport 6443,2379:2380,10250:10252,6783 -j ACCEPT ; sudo iptables -D INPUT -m multiport -p udp -s \$HOST --dport 6783,6784 -j ACCEPT ; done ; sudo iptables-save | sudo tee /etc/iptables/rules.v4"
		done
		;;
	*)
		echo $(basename $0) preflight
		echo $(basename $0) init master operator network
		echo $(basename $0) join host operator
		echo $(basename $0) cni master operator
		echo $(basename $0) leave master operator host
		echo $(basename $0) status master operator
		echo $(basename $0) master-network-up operator host1 host2 ...
		echo $(basename $0) master-network-down operator host1 host2 ...
		;;
esac
