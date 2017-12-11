cd /root/VMHost/data/sipp_toolkit/
sipp -sf register.xml -inf callee.csv -i voip.sip -nd -t u1 -r 1 -rp 1s 192.168.1.114

cd /root/VMHost/data/sipp_toolkit/
sipp -sf uas_signal.xml -inf caller.csv -i voip.sip -p 50603 -t un 192.168.1.114

cd /root/VMHost/data/sipp_toolkit/
sipp -sf uac_signal.xml -inf caller.csv -inf callee.csv -i voip.sip -p 50603 -nd -t u1 -r 1 -rp 1s 192.168.1.114


sipp -s subsub_0001 -au subsub_0001 -ap subsub_pwd_0001 -nd -t u1 -r 1 -rp 1s -inf /root/VMHost/data/sipp_toolkit/callee.csv -sf /root/VMHost/data/sipp_toolkit/register.xml -i voip.sipwise.local 127.0.0.1

sipp -s subsub_0002 -au subsub_0002 -ap subsub_pwd_0002 -nd -t u1 -r 1 -rp 1s -sf /root/VMHost/data/sipp_toolkit/uas_signal_parameters.xml -i voip.sipwise.local 127.0.0.1

sipp -s subsub_0001 -au subsub_0001 -ap subsub_pwd_0001 -nd -t u1 -r 1 -rp 1s -key service_caller subsub_0002 -key remote_ip_caller voip.sipwise.local -key remote_port_caller 5060 -sf /root/VMHost/data/sipp_toolkit/uac_signal_parameters.xml -i voip.sipwise.local 127.0.0.1

#sipp -s subsub_0001 -au subsub_0001 -ap subsub_pwd_0001 -nd -t u1 -r 1 -rp 1s -inf /root/VMHost/data/sipp_toolkit/caller.csv -inf /root/VMHost/data/sipp_toolkit/callee.csv -sf /root/VMHost/data/sipp_toolkit/uac_signal.xml -i voip.sipwise.local 127.0.0.1

#sipp -s subsub_0001 -au subsub_0001 -ap subsub_pwd_0001 -nd -t u1 -r 1 -rp 1s -inf /root/VMHost/data/sipp_toolkit/caller.csv -inf /root/VMHost/data/sipp_toolkit/callee.csv -sf /root/VMHost/data/sipp_toolkit/uac_signal_parameters.xml -i voip.sipwise.local 127.0.0.1

