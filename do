#!/bin/bash

SECRET_SSHPORT=`cat /etc/ssh/sshd_config| grep '^Port' | cut -d ' ' -f 2 || echo 22`
if [ "$SSHPORT" == "" ] ; then SSHPORT=${SECRET_SSHPORT} ; fi
[[ "${SECRET}" == "" ]] && SECRET=~/.secret
echo SECRET=${SECRET} SSHPORT=$SSHPORT

WEAVE_PASSWORD_FILE=${SECRET}/.kube/weave_password
[[ -e "$WEAVE_PASSWORD_FILE" ]] && export WEAVE_PASSWORD=$(cat ${WEAVE_PASSWORD_FILE})

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
		mkdir -p ${SECRET}/.kube
		sudo kubeadm init 2>&1 | tee ${SECRET}/.kube/init
		mkdir -p $HOME/.kube
		sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
		sudo chown $(id -u):$(id -g) $HOME/.kube/config
		kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
		;;
	"master-join")
		shift
		HOST=$1
		TOKEN=$2
		SHA=$3
		sudo kubeadm join --token=${TOKEN} ${HOST}:6443 --discovery-token-ca-cert-hash ${SHA}
		;;
	"master-network-up")
		shift
		USER=$1
		shift
		HOSTS=$*
		SECRET=${SECRET} $0 master-network-down $USER $HOSTS
		for HOST in $HOSTS
		do
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
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "for HOST in $HOSTS ; do sudo iptables -D INPUT -m multiport -p tcp -s \$HOST --dport 6443,2379:2380,10250:10252 -j ACCEPT ; sudo iptables -D INPUT -m multiport -p tcp -s \$HOST --sport 6443,2379:2380,10250:10252 -j ACCEPT ; done ; sudo iptables-save | sudo tee /etc/iptables/rules.v4"
		done
		;;
	*)
		echo $(basename $0) preflight
		echo $(basename $0) init
		echo $(basename $0) master-join token
		echo $(basename $0) master-network-up operator host1 host2 ...
		echo $(basename $0) master-network-down operator host1 host2 ...
		;;
esac
