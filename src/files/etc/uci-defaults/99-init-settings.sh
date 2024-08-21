#!/bin/sh

# Disable opkg signature check
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf

# Set Timezone to Asia/Jakarta
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci commit

# Set argon as default theme
uci set argon.@global[0].mode='light'
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit

# add cron job for modem rakitan
echo '#auto renew ip lease for modem rakitan' >>/etc/crontabs/root
echo '#30 3 * * * echo AT+CFUN=4 | atinout - /dev/ttyUSB1 - && ifdown mm && sleep 3 && ifup mm' >>/etc/crontabs/root
echo '#30 3 * * * ifdown fibocom && sleep 3 && ifup fibocom' >>/etc/crontabs/root
/etc/init.d/cron restart

exit 0
