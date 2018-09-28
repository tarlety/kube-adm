#!/bin/bash

SECRET_SSHPORT=`cat /etc/ssh/sshd_config| grep '^Port' | cut -d ' ' -f 2 || echo 22`
if [ "$SSHPORT" == "" ] ; then SSHPORT=${SECRET_SSHPORT} ; fi
[[ "${SECRET}" == "" ]] && SECRET=~/.secret
echo SECRET=${SECRET} SSHPORT=$SSHPORT

case $1 in
	"preflight")
		# ref: https://kubernetes.io/docs/setup/independent/install-kubeadm/
		sudo apt update -y
		sudo apt install -y apt-transport-https curl
		curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
		sudo apt update -y
		sudo apt install -y kubelet kubeadm kubectl
		sudo apt-mark hold kubelet kubeadm kubectl
		sudo swapoff -a
		;;
	"init")
		shift
		HOST=$1
		USER=$2
		mkdir -p ${SECRET}/.kube
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo kubeadm init 2>&1" | tee ${SECRET}/.kube/init
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "mkdir -p \$HOME/.kube"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "kubectl apply -f https://cloud.weave.works/k8s/net?k8s-version=\$(kubectl version | base64 | tr -d '\n')"
		;;
	"join")
		shift
		HOST=$1
		USER=$2
		JOINCMD=`cat ${SECRET}/.kube/init | grep "kubeadm join" | sed 's/^ *//'`
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo ${JOINCMD}"
		;;
	"status")
		shift
		HOST=$1
		USER=$2
		echo "## nodes"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "kubectl get nodes"
		echo "## pods"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "kubectl get pods --all-namespaces"
		echo "## weave"
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "kubectl exec -n kube-system \$(kubectl get pods --all-namespaces | grep weave | sed 's/  */ /g' | cut -d ' ' -f 2 | tail -n 1) -c weave -- /home/weave/weave --local status"
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
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "for HOST in $HOSTS ; do sudo iptables -I INPUT -m multiport -p tcp -s \$HOST --dport 6443,2379:2380,10250:10252 -j ACCEPT ; sudo iptables -I INPUT -m multiport -p tcp -s \$HOST --sport 6443,2379:2380,10250:10252 -j ACCEPT ; done ; sudo iptables-save | sudo tee /etc/iptables/rules.v4"
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
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "for HOST in $HOSTS ; do sudo iptables -D INPUT -m multiport -p tcp -s \$HOST --dport 6443,2379:2380,10250:10252 -j ACCEPT ; sudo iptables -D INPUT -m multiport -p tcp -s \$HOST --sport 6443,2379:2380,10250:10252 -j ACCEPT ; done ; sudo iptables-save | sudo tee /etc/iptables/rules.v4"
		done
		;;
	*)
		echo $(basename $0) preflight
		echo $(basename $0) init host operator
		echo $(basename $0) join host operator
		echo $(basename $0) status host operator
		echo $(basename $0) master-network-up operator host1 host2 ...
		echo $(basename $0) master-network-down operator host1 host2 ...
		;;
esac
