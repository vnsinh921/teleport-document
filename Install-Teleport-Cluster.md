### I. Giới thiệu và kiến trúc Teleport
### 1. Giới thiệu
-   Teleport là một proxy truy cập đa giao thức, nhận biết danh tính, có thể hiểu các giao thức: SSH, HTTPS, RDP, Kubernetes API, MySQL, MongoDB và PostgreSQL.
-   Teleport cho phép truy cập an toàn thuận tiện vào các tài nguyên sau NAT như:
    - SSH nodes 
    - Kubernetes clusters
    - PostgreSQL, MongoDB, CockroachDB and MySQL databases
    - Internal Web apps
    - Windows Hosts
    - Networked servers

### 2. Kiến trúc cơ bản
<img src="./images/teleport/overview.png" />  

<img src="./images/teleport/overview1.png" />  

### 2.1 Khởi tạo kết nối từ Client
<img src="./images/teleport/initiate.png" />  

- Client khởi tạo kết nối từ SSH tới proxy từ giao diện UI hoặc CLI. Khi thiết lập kết nối Client phải cung cấp certificate của nó. Client luôn luôn phải kết nối qua proxy với 2 lý do:
    -   Các node không phải lúc nào cũng có thể truy cập từ một network bên ngoài
    -   Proxy ghi lại các phiên SSH và theo dõi hoạt động của người dùng

### 2.2 Xác thực certificate của client
<img src="./images/teleport/cert_ok.png" />  

- Proxy sẽ kiểm tra xem certificate đã gửi đã được auth server ký trước đó hay chưa

<img src="./images/teleport/cert_invalid.png" />

- Nếu không có certificate nào được cung cấp trước đó (đăng nhập lần đầu tiên) hoặc nếu certificate đã hết hạn, proxy sẽ từ chối kết nối và yêu cầu client đăng nhập tương tác bằng mật khẩu và xác thực 2FA(OTP) nếu được bật.
- Nếu thông tin xác thực là chính xác, auth server sẽ tạo và ký ccertificate mới và trả lại certificate đó cho client thông qua proxy.

### 2.3: Tra cứu Node
<img src="./images/teleport/node_lookup.png" />

-   Ở bước này, proxy xác định vị trí node được yêu cầu trong một cụm. Có ba cơ chế tra cứu mà proxy sử dụng để tìm địa chỉ IP của node:
    -   Sử dụng DNS để phân giải tên do Client yêu cầu.
    -   Hỏi Auth Server nếu có một Node được đăng ký với tên node request kết nối.
    -   Yêu cầu Auth Server tìm một node (hoặc các nodes) có nhãn phù hợp với tên được yêu cầu.
-   Nếu node được định vị, proxy sẽ thiết lập kết nối giữa Client và node được yêu cầu. Sau đó, node đích bắt đầu ghi lại phiên, gửi lịch sử phiên đến Auth server để được lưu trữ.

### 2.4 Xác thực certificate Node

<img src="./images/teleport/node_cluster_auth.png" />

-   Khi node nhận được yêu cầu kết nối, node sẽ kiểm tra với Auth Server để xác thực certificate của node và xác nhận tư cách thành viên Cluster của Node.
-   Nếu certificate node hợp lệ, node được phép truy cập Auth Server API cung cấp quyền truy cập vào thông tin về các node và người dùng trong Cluster.

### 2.5 Cấp quyền truy cập Node của user

<img src="./images/teleport/user_node_access.png" />

-   Node yêu cầu Auth Server cung cấp danh sách người dùng hệ điều hành (ánh xạ người dùng) cho Client kết nối, để đảm bảo Client được phép sử dụng thông tin đăng nhập hệ điều hành được yêu cầu.
-   Cuối cùng, Client được phép tạo kết nối SSH tới một node.

<img src="./images/teleport/proxy_client_connect.png" />

> Architecture Introduction: https://goteleport.com/docs/architecture/overview/

### II. Cài đặt Teleport 
### 2.1 Mô hình
-   Client network: 10.0.0.0/24
-   Auth server & proxy server network:
-   10.0.0.0/24
-   10.20.0.0/24
-   Node server network: 10.20.0.0/24
-   IP Planning
<img src="./images/teleport/ip_plan.png" />

-  OS Cài đặt:
    -   Teleport-access (Ubuntu 20.04)
    -   Teleport-node   (Centos 7 hoặc Ubuntu 20.04)

### 2.1 Cài đặt Teleport Auth server và Proxy server
-   Thiết lập hostname và timezone:
    ```sh
    hostnamectl set-hostname teleport-access
    timedatectl set-timezone Asia/Ho_Chi_Minh
    ```
-   Download Teleport's PGP public key
    ```sh
    sudo curl https://deb.releases.teleport.dev/teleport-pubkey.asc \
    -o /usr/share/keyrings/teleport-archive-keyring.asc
    ```
-   Add the Teleport APT repository
    ```sh
    cat<<EOF>/etc/apt/sources.list.d/teleport.list
    deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc] https://deb.releases.teleport.dev/ stable main
    EOF
    ```
- Update và Install Teleport package
    ```sh
    apt-get update
    apt-get install teleport -y
- Tạo file systemd teleport.service
    ```sh
    cat<<EOF>/lib/systemd/system/teleport.service
    [Unit]
    Description=Teleport SSH Service
    After=network.target

    [Service]
    Type=simple
    Restart=on-failure
    EnvironmentFile=-/etc/default/teleport
    ExecStart=/usr/local/bin/teleport start --pid-file=/run/teleport.pid --config=/etc/teleport.yaml
    ExecReload=/bin/kill -HUP $MAINPID
    PIDFile=/run/teleport.pid
    LimitNOFILE=8192

    [Install]
    WantedBy=multi-user.target
    EOF
    ```
- Reload daemon systemd
    ```sh
    systemctl daemon-reload
    ```
- Tạo file config teleport.yaml

    ```sh
    cat<<EOF>/etc/teleport.yaml
    version: v2
    teleport:
      nodename: teleport-access
      data_dir: /var/lib/teleport
      log:
    output: /var/log/teleport.log
    severity:
      ca_pin: 
      auth_token: 7d8ae42392ae8b7503dd3b76ea76aca6960689b5157f8523

    auth_service:
      enabled: "yes"
      cluster_name: "teleport-demo"
      listen_addr: 0.0.0.0:3025
      tokens:
      - proxy,node:7d8ae42392ae8b7503dd3b76ea76aca6960689b5157f8523
      authentication:
        type: local
        second_factor: otp

    ssh_service:
      enabled: "yes"
      labels:
        env: example
        commands:
        - name: hostname
        command: [hostname]
        period: 1m0s

    proxy_service:
      enabled: "yes"
      listen_addr: 0.0.0.0:3023
      web_listen_addr: 10.0.0.5:3080
      tunnel_listen_addr: 0.0.0.0:3024
      public_addr: 10.0.0.5:3080
      https_keypairs: []
      acme: {}
    EOF
    ```
-   Restart service teleport
    ```sh
        service teleport restart
        service teleport status
        ● teleport.service - Teleport SSH Service
        Loaded: loaded (/lib/systemd/system/teleport.service; enabled; vendor preset: enabled)
        Active: active (running) since Thu 2022-03-17 21:50:32 +07; 2min 52s ago
        Main PID: 14004 (teleport)
        Tasks: 9 (limit: 2237)
        Memory: 34.7M
        CGroup: /system.slice/teleport.service
        └─14004 /usr/local/bin/teleport start --pid-file=/run/teleport.pid --config=/etc/teleport.yaml

        Mar 17 21:50:32 teleport-access systemd[1]: Started Teleport SSH Service.
        Mar 17 21:50:33 teleport-access teleport[14004]: [AUTH] Auth service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 10.0.0.5:3025.
        Mar 17 21:50:34 teleport-access teleport[14004]: [NODE] Service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3022.
        Mar 17 21:50:34 teleport-access teleport[14004]: [PROXY]Reverse tunnel service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3024.
        Mar 17 21:50:34 teleport-access teleport[14004]: [PROXY]Web proxy service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 10.0.0.5:3080.
        Mar 17 21:50:34 teleport-access teleport[14004]: [PROXY]SSH proxy service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3023.

    ```
-   Check log teleport
    ```sh
        root@teleport-access:~# cat /var/log/teleport.log 
        2022-03-17T21:50:32+07:00 [AUTH]      INFO Updating cluster networking configuration: Kind:"cluster_networking_config" Version:"v22022-03-17T21:50:33+07:00 [PROC:1]    INFO Admin has obtained credentials to connect to the cluster. service/connect.go:416
        2022-03-17T21:50:33+07:00 [PROC:1]    INFO The process successfully wrote the credentials and state of Admin to the disk. service/connect.go:457
        2022-03-17T21:50:33+07:00 [PROC:1]    INFO Service auth is creating new listener on 0.0.0.0:3025. service/signals.go:213
        2022-03-17T21:50:33+07:00 [AUTH:1]    INFO Starting Auth service with PROXY protocol support. service/service.go:1341
        2022-03-17T21:50:33+07:00 [AUTH:1]    WARN Configuration setting auth_service/advertise_ip is not set. guessing 10.0.0.5:3025. service/service.go:1419
        2022-03-17T21:50:33+07:00     WARN No TLS Keys provided, using self-signed certificate. service/service.go:3885
        2022-03-17T21:50:33+07:00     WARN Generating self-signed key and cert to /var/lib/teleport/webproxy_key.pem /var/lib/teleport/webproxy_cert.pem. service/service.go:3903
        2022-03-17T21:50:33+07:00 [AUTH:1]    INFO Auth service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 10.0.0.5:3025. utils/cli.go:275
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Proxy has obtained credentials to connect to the cluster. service/connect.go:416
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO The process successfully wrote the credentials and state of Proxy to the disk. service/connect.go:457
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Proxy: features loaded from auth server: Kubernetes:true App:true DB:true Desktop:true  service/connect.go:71
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Service proxy:ssh is creating new listener on 0.0.0.0:3023. service/signals.go:213
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Service proxy:web is creating new listener on 10.0.0.5:3080. service/signals.go:213
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Service proxy:tunnel is creating new listener on 0.0.0.0:3024. service/signals.go:213
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Node has obtained credentials to connect to the cluster. service/connect.go:416
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO The process successfully wrote the credentials and state of Node to the disk. service/connect.go:457
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Node: features loaded from auth server: Kubernetes:true App:true DB:true Desktop:true  service/connect.go:71
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO Service node is creating new listener on 0.0.0.0:3022. service/signals.go:213
        2022-03-17T21:50:34+07:00 [NODE:1]    INFO Service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3022 sqlite cache will store frequently accessed items. service/service.go:1986
        2022-03-17T21:50:34+07:00 [NODE:1]    INFO Service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3022. utils/cli.go:275
        2022-03-17T21:50:34+07:00     INFO Loading TLS certificate /var/lib/teleport/webproxy_cert.pem and key /var/lib/teleport/webproxy_key.pem. service/service.go:3368
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO Reverse tunnel service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3024. utils/cli.go:275
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO Starting 9.0.1:v9.0.1-0-g7bbe6f15c on 0.0.0.0:3024 using sqlite cache will store frequently accessed items service/service.go:2870
        2022-03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating directory /var/lib/teleport/log. service/service.go:2115
        2022-03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating directory /var/lib/teleport/log/upload. service/service.go:2115
        2022-03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating directory /var/lib/teleport/log/upload/sessions. service/service.go:2115
        2022-03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating2022-03-17T21:50:34+07:00 [PROXY:AGE] INFO Starting reverse tunnel agent pool. service/service.go:3033
        2022-03-17T21:50:34+07:00 [PROXY:PRO] INFO Starting Kube proxy on . service/service.go:3092
        -03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating directory /var/lib/teleport/log/upload. service/service.go:2115
        2022-03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating directory /var/lib/teleport/log/upload/streaming. service/service.go:2115
        2022-03-17T21:50:34+07:00 [AUDIT:1]   INFO Creating directory /var/lib/teleport/log/upload/streaming/default. service/service.go:2115
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO Web proxy service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 10.0.0.5:3080. utils/cli.go:275
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO Web proxy service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 10.0.0.5:3080. service/service.go:2959
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO SSH proxy service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on 0.0.0.0:3023. utils/cli.go:275
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO SSH proxy service 9.0.1:v9.0.1-0-g7bbe6f15c is starting on {0.0.0.0:3023 tcp } service/service.go:3000
        2022-03-17T21:50:34+07:00 [PROC:1]    INFO The new service has started successfully. Starting syncing rotation status with period 10m0s. service/connect.go:469
        2022-03-17T21:50:34+07:00 [DB:SERVIC] INFO Starting Postgres proxy server on 10.0.0.5:3080. service/service.go:3158
        2022-03-17T21:50:34+07:00 [DB:SERVIC] INFO Starting Database TLS proxy server on 10.0.0.5:3080. service/service.go:3176
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO Starting proxy gRPC server on 10.0.0.5:3080. service/service.go:3210
        2022-03-17T21:50:34+07:00 [PROXY:SER] INFO Starting TLS ALPN SNI proxy server on 10.0.0.5:3080. service/service.go:3239
        2022-03-17T21:50:36+07:00 [PROXY:1]   WARN Restart watch on error: empty proxy list. resource-kind:proxy services/watcher.go:218
        root@teleport-access:~# 
    ```
-   Check ca_pin Auth server
    ```sh
    root@teleport-access:~# tctl status
    Cluster  teleport-demo                                                           
    Version  9.0.1                                                                   
    Host CA  never updated                                                           
    User CA  never updated                                                           
    Jwt CA   never updated                                                           
    CA pin   sha256:8fb62b491b1c04048befc4a70b5cd4686b5de0b9acd5b4bf6629b5568811b314
    ```
-   Create role admin
    ```sh
    cat<<EOF>admin.yaml
    #
    # Example: Legacy Default Admin Role
    # Tip: For 6.0+ clusters, please use 'editor' for configuring Teleport
    #
    kind: role
    metadata:
    name: admin
    spec:
    allow:
        kubernetes_groups:
        - '{{internal.kubernetes_groups}}'
        windows_desktop_logins:
        - '{{internal.windows_logins}}'
        logins:
        - '{{internal.logins}}'
        - root
        node_labels:
        '*': '*'
        rules:
        - resources:
        - '*'
        verbs:
        - '*'
    deny:
        logins: null
    options:
        cert_format: standard
        enhanced_recording:
        - command
        - network
        forward_agent: true
        max_session_ttl: 30h0m0s
        port_forwarding: true
    version: v3
    EOF
    tctl create -f admin.yaml
    ```
-   Create role user
    ```sh
    cat<<EOF>user.yaml
    #
    # Example: Legacy Default Admin Role
    # Tip: For 6.0+ clusters, please use 'editor' for configuring Teleport
    #
    kind: role
    metadata:
    name: user
    spec:
    allow:
        kubernetes_groups:
        - '{{internal.kubernetes_groups}}'
        windows_desktop_logins:
        - '{{internal.windows_logins}}'
        logins:
        - '{{internal.logins}}'
        node_labels:
        '*': '*'
        rules:
        - resources:
        - role
        verbs:
        - list
        - read
        - resources:
        - session
        verbs:
        - list
        - read
        - resources:
        - trusted_cluster
        verbs:
        - connect
        - list
        - read
    deny:
        logins: null
    options:
        cert_format: standard
        enhanced_recording:
        - command
        - network
        forward_agent: true
        max_session_ttl: 30h0m0s
        port_forwarding: true
    version: v3
    EOF
    tctl create -f user.yaml
    ```
-   Create user admin
    ```sh
    tctl users add admin --logins=root --roles=admin
    ```
    ```sh
    root@teleport-access:~# tctl users add admin --logins=root --roles=admin
    User "admin" has been created but requires a password. Share this URL with the user to complete user setup, link is valid for 1h:
    https://10.0.0.5:3080/web/invite/25962b5cc23c07921b87de99b766f888

    NOTE: Make sure 10.0.0.5:3080 points at a Teleport proxy which users can access.

    ```
-   Thiết lập password và OTP cho user bằng cách click vào url: https://10.0.0.5:3080/web/invite/25962b5cc23c07921b87de99b766f888

    <img src="./images/teleport/adduser.png" />
-   Kết quả đạt được
     <img src="./images/teleport/succes.png" />    
-   Creater user sinhtv
    ```sh
    tctl users add sinhtv --logins=sinhtv --roles=user
    ```
    ```sh
    root@teleport-access:~# tctl users add sinhtv --logins=sinhtv --roles=user
    User "sinhtv" has been created but requires a password. Share this URL with the user to complete user setup, link is valid for 1h:
    https://10.0.0.5:3080/web/invite/2f9013488d6e4d421ef8e83ed5c5bbdd

    NOTE: Make sure 10.0.0.5:3080 points at a Teleport proxy which users can access.
    root@teleport-access:~# 
    ```

### 2.2 Cài đăt teleport Node
-   Ubuntu OS:
    -   Download Teleport's PGP public key
        ```sh
        curl https://deb.releases.teleport.dev/teleport-pubkey.asc \
        -o /usr/share/keyrings/teleport-archive-keyring.asc
        ```
    -   Add the Teleport APT repository
        ```sh
        cat<<EOF>/etc/apt/sources.list.d/teleport.list
        deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc] https://deb.releases.teleport.dev/ stable main
        EOF
        ```
    -   Update & Install teleport package
        ```sh
        apt-get update
        apt-get install teleport -y
        ```
-   Centos OS
    -   Cài đặt gói epel-release
        ```sh
        yum install epel-release -y
        ```
    -   Add teleport repo
        ```sh
        yum-config-manager --add-repo https://rpm.releases.teleport.dev/teleport.repo
        ```
    -   Install teleport package
        ```sh
        yum install teleport -y
        ```
- Tạo file systemd teleport.service
    ```sh
    cat<<EOF>/lib/systemd/system/teleport.service
    [Unit]
    Description=Teleport SSH Service
    After=network.target

    [Service]
    Type=simple
    Restart=on-failure
    EnvironmentFile=-/etc/default/teleport
    ExecStart=/usr/local/bin/teleport start --pid-file=/run/teleport.pid --config=/etc/teleport.yaml --roles=node
    ExecReload=/bin/kill -HUP $MAINPID
    PIDFile=/run/teleport.pid
    LimitNOFILE=8192

    [Install]
    WantedBy=multi-user.target
    EOF
    ```
- Reload daemon systemd
    ```sh
    systemctl daemon-reload
    ```
- Tạo file config teleport.yaml

    ```sh
    cat<<EOF>/etc/teleport.yaml
    teleport:
      nodename: pg-1 # Tnay đổi theo tên node
      data_dir: /var/lib/teleport
      ca_pin: "sha256:8fb62b491b1c04048befc4a70b5cd4686b5de0b9acd5b4bf6629b5568811b314"
      auth_token: 7d8ae42392ae8b7503dd3b76ea76aca6960689b5157f8523

      auth_servers: 
        - 10.20.0.5:3025

      log:
        output: /var/log/teleport.log
        severity:

    ssh_service:
        enabled: yes
        listen_addr: 10.20.0.11:3025 # Thay đổi theo IP node
        public_addr: 10.20.0.11:3025 # Thay đổi theo IP node
        labels:
            role: node
            type: teleport-client
        commands:
        - name: hostname
        command: [hostname]
        period: 1m0s

    EOF
    ```
-   Restart service teleport 
    ```sh
    service teleport restart
    service teleport status
    ```
    ```sh
    [root@localhost ~]# systemctl status teleport
    ● teleport.service - Teleport SSH Service
    Loaded: loaded (/usr/lib/systemd/system/teleport.service; disabled; vendor preset: disabled)
    Active: active (running) since Thu 2022-03-17 22:31:21 +07; 16min ago
    Main PID: 9720 (teleport)
    CGroup: /system.slice/teleport.service
            └─9720 /usr/local/bin/teleport start --pid-file=/run/teleport.pid --config=/etc/teleport.yaml --roles=node

    Mar 17 22:31:21 localhost.localdomain systemd[1]: Started Teleport SSH Service.
    Mar 17 22:31:21 localhost.localdomain teleport[9720]: [NODE]         Service 9.0.1:v9.0.1-0-g7bbe6f1 is starting on 10.20.0.11:3025.
    ```
### 2.3 Check trạng thái node trên server: Teleport-access
-   Server teleport-access
    ```sh
    tctl nodes ls
    ```
    ```sh
    root@teleport-demo:~# tctl nodes ls
    Nodename               UUID                                 Address         Labels                                       
    ---------------------- ------------------------------------ --------------- -------------------------------------------- 
    teleport-access        c06697a5-ecd2-44e1-b710-d8109bee9c38 127.0.0.1:3022  hostname=teleport-demo,role=node,type=teleport-client
    pg-1                   9da0ac8b-0254-42e3-9335-4338f0267ae5 10.20.0.11:3025 hostname=pg-1,role=node,type=teleport-client 
    pg-2                   f779ccda-ade0-414d-b1d0-1cf25b9dfab0 10.20.0.12:3025 hostname=pg-2,role=node,type=teleport-client 
    pg-3                   fd076dae-05e0-4ef7-a4ac-a578235d0e32 10.20.0.13:3025 hostname=pg-3,role=node,type=teleport-client 
    root@teleport-demo:~# 
    ```
-   Web UI
<img src="./images/teleport/node_cluster.png" />      

### III. Teleport CLI command
### 3.1 TSH command
-   Từ máy Client IP 10.0.0.1 cần kết nối tới host Private dải IP 10.20.0.xx
-   Tiến hành kiểm tra network tới các node bằng lệnh
    ```sh
    sinhtv@HP-348-G7:~$ ip a
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        inet 127.0.0.1/8 scope host lo
           valid_lft forever preferred_lft forever
    2: eno1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN group default qlen 1000
        link/ether bc:e9:2f:c9:65:db brd ff:ff:ff:ff:ff:ff
        altname enp1s0
    3: wlo1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
        link/ether 8c:c8:4b:c5:93:23 brd ff:ff:ff:ff:ff:ff
        altname wlp2s0
        inet 10.100.0.183/24 brd 10.100.0.255 scope global dynamic noprefixroute wlo1
           valid_lft 6966sec preferred_lft 6966sec
    6: vmnet8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN group default qlen 1000
        link/ether 00:50:56:c0:00:08 brd ff:ff:ff:ff:ff:ff
        inet 10.0.0.1/24 brd 10.0.0.255 scope global vmnet8
           valid_lft forever preferred_lft forever
    sinhtv@HP-348-G7:~$ ping -c4 10.20.0.11
    PING 10.20.0.11 (10.20.0.11) 56(84) bytes of data.

    --- 10.20.0.11 ping statistics ---
    4 packets transmitted, 0 received, 100% packet loss, time 3071ms

    sinhtv@HP-348-G7:~$ ping -c4 10.20.0.12
    PING 10.20.0.12 (10.20.0.12) 56(84) bytes of data.

    --- 10.20.0.12 ping statistics ---
    4 packets transmitted, 0 received, 100% packet loss, time 3075ms

    sinhtv@HP-348-G7:~$ ping -c4 10.20.0.13
    PING 10.20.0.13 (10.20.0.13) 56(84) bytes of data.

    --- 10.20.0.13 ping statistics ---
    4 packets transmitted, 0 received, 100% packet loss, time 3055ms

    sinhtv@HP-348-G7:~$ ping -c4 10.0.0.5
    PING 10.0.0.5 (10.0.0.5) 56(84) bytes of data.
    64 bytes from 10.0.0.5: icmp_seq=1 ttl=64 time=0.867 ms
    64 bytes from 10.0.0.5: icmp_seq=2 ttl=64 time=3.28 ms
    64 bytes from 10.0.0.5: icmp_seq=3 ttl=64 time=0.490 ms
    64 bytes from 10.0.0.5: icmp_seq=4 ttl=64 time=0.539 ms

    --- 10.0.0.5 ping statistics ---
    4 packets transmitted, 4 received, 0% packet loss, time 3006ms
    rtt min/avg/max/mdev = 0.490/1.294/3.282/1.156 ms
    sinhtv@HP-348-G7:~$ 

    ```
-   Login vào cluster
    ```sh
    tsh login --proxy=10.0.0.5:3080 --user=sinhtv --insecure
    ```
-   Nhập password & OTP user sinhtv sau đó kiểm tra trạng thái kết nối
    ```sh
    sinhtv@HP-348-G7:~$ tsh login --proxy=10.0.0.5:3080 --user=sinhtv --insecure
    Enter password for Teleport user sinhtv:
    Enter your OTP token:
    709166
    WARNING: You are using insecure connection to SSH proxy https://10.0.0.5:3080
    > Profile URL:        https://10.0.0.5:3080
      Logged in as:       sinhtv
      Cluster:            teleport-demo
      Roles:              user
      Logins:             sinhtv
      Kubernetes:         enabled
      Valid until:        2022-03-19 10:37:04 +0700 +07 [valid for 12h0m0s]
      Extensions:         permit-agent-forwarding, permit-port-forwarding, permit-pty

    sinhtv@HP-348-G7:~$ 

    ```
-   Liệt kê các node trong cluster
    ```sh
    sinhtv@HP-348-G7:~$ tsh ls
    Node Name       Address         Labels                                                
    --------------- --------------- ----------------------------------------------------- 
    pg-1            10.20.0.11:3025 hostname=pg-1,role=node,type=teleport-client          
    pg-2            10.20.0.12:3025 hostname=pg-2,role=node,type=teleport-client          
    pg-3            10.20.0.13:3025 hostname=pg-3,role=node,type=teleport-client          
    teleport-access 127.0.0.1:3022  hostname=teleport-demo,role=node,type=teleport-client 

    sinhtv@HP-348-G7:~$ 
    ```
-   Kết nối tới node trong list nodes bằng giao thức teleport ssh
    ```sh
    tsh ssh [USER]@[IP NODE] 
        hoặc
    tsh ssh [USER]@[HOSTNAME]
    ```
    ```sh
    sinhtv@HP-348-G7:~$ tsh ssh sinhtv@pg-1
    [sinhtv@pg-1 ~]$ ip a
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        inet 127.0.0.1/8 scope host lo
           valid_lft forever preferred_lft forever
        inet6 ::1/128 scope host 
           valid_lft forever preferred_lft forever
    2: ens34: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
        link/ether 00:0c:29:74:59:d6 brd ff:ff:ff:ff:ff:ff
        inet 10.20.0.11/24 brd 10.20.0.255 scope global noprefixroute ens34
           valid_lft forever preferred_lft forever
        inet6 fe80::69a4:4a4b:437f:9fad/64 scope link noprefixroute 
           valid_lft forever preferred_lft forever
    [sinhtv@pg-1 ~]$ 
    ```
    
    ```sh
    sinhtv@HP-348-G7:~$ tsh ssh sinhtv@pg-2
    [sinhtv@pg-2 ~]$ ip a
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        inet 127.0.0.1/8 scope host lo
           valid_lft forever preferred_lft forever
        inet6 ::1/128 scope host 
           valid_lft forever preferred_lft forever
    2: ens34: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
        link/ether 00:0c:29:7a:bb:64 brd ff:ff:ff:ff:ff:ff
        inet 10.20.0.12/24 brd 10.20.0.255 scope global noprefixroute ens34
           valid_lft forever preferred_lft forever
        inet6 fe80::69a4:4a4b:437f:9fad/64 scope link tentative noprefixroute dadfailed 
           valid_lft forever preferred_lft forever
        inet6 fe80::a43d:6adf:ea44:57/64 scope link noprefixroute 
           valid_lft forever preferred_lft forever
    [sinhtv@pg-2 ~]$ 
    ```
    ```sh
    sinhtv@HP-348-G7:~$ tsh ssh sinhtv@10.20.0.13
    [sinhtv@pg-3 ~]$ ip a
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        inet 127.0.0.1/8 scope host lo
           valid_lft forever preferred_lft forever
        inet6 ::1/128 scope host 
           valid_lft forever preferred_lft forever
    2: ens34: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
        link/ether 00:0c:29:7b:55:7b brd ff:ff:ff:ff:ff:ff
        inet 10.20.0.13/24 brd 10.20.0.255 scope global noprefixroute ens34
           valid_lft forever preferred_lft forever
        inet6 fe80::a43d:6adf:ea44:57/64 scope link tentative noprefixroute dadfailed 
           valid_lft forever preferred_lft forever
        inet6 fe80::69a4:4a4b:437f:9fad/64 scope link tentative noprefixroute dadfailed 
           valid_lft forever preferred_lft forever
        inet6 fe80::c163:4779:c750:b173/64 scope link noprefixroute 
           valid_lft forever preferred_lft forever
    [sinhtv@pg-3 ~]$ 
    ```
-   SCP file từ máy local tới node teleport
    ```sh
    tsh scp [FILE_NAME] [USER]@[IP NODE]:~/
    ```
    ```sh
    sinhtv@HP-348-G7:~$ tsh scp Dockerfile sinhtv@pg-1:~/
    -> Dockerfile (556)
    sinhtv@HP-348-G7:~$ tsh ssh sinhtv@pg-1
    [sinhtv@pg-1 ~]$ ls
    Dockerfile
    [sinhtv@pg-1 ~]$ 
    ```
-   SCP file từ  node teleport về máy local
    ```sh
    tsh scp  [USER]@[IP NODE]:~/[FILE_NAME_ON_NODE] ~/
    ```
    ```sh
    sinhtv@HP-348-G7:~$ tsh scp sinhtv@pg-1:~/pg-1.file ./
    <- pg-1.file (556)
    sinhtv@HP-348-G7:~$ ls -l |grep pg-1.file
    -rw-rw-r--  1 sinhtv sinhtv   556 Mar 18 22:46 pg-1.file
    sinhtv@HP-348-G7:~$ 
    ```
-   TSH list command: tsh help
    ```sh
    sinhtv@HP-348-G7:~$ tsh help
    Usage: tsh [<flags>] <command> [<args> ...]

    TSH: Teleport Authentication Gateway Client

    Flags:
      -l, --login                    Remote host login
          --proxy                    SSH proxy address
          --user                     SSH proxy user [sinhtv]
          --ttl                      Minutes to live for a SSH session
      -i, --identity                 Identity file
          --cert-format              SSH certificate format
          --insecure                 Do not verify server's certificate and host name. Use only in test environments
          --auth                     Specify the type of authentication connector to use.
          --skip-version-check       Skip version checking between server and client.
      -d, --debug                    Verbose logging to stdout
      -k, --add-keys-to-agent        Controls how keys are handled. Valid values are [auto no yes only].
          --enable-escape-sequences  Enable support for SSH escape sequences. Type '~?' during an SSH session to list supported sequences. Default is enabled.
          --bind-addr                Override host:port used when opening a browser for cluster logins
      -J, --jumphost                 SSH jumphost

    Commands:
      help         Show help.
      version      Print the version
      ssh          Run shell or execute a command on a remote SSH node
      aws          Access AWS API.
      apps ls      List available applications.
      apps login   Retrieve short-lived certificate for an app.
      apps logout  Remove app certificate.
      apps config  Print app connection information.
      proxy ssh    Start local TLS proxy for ssh connections when using Teleport in single-port mode
      proxy db     Start local TLS proxy for database connections when using Teleport in single-port mode
      db ls        List all available databases.
      db login     Retrieve credentials for a database.
      db logout    Remove database credentials.
      db env       Print environment variables for the configured database.
      db config    Print database connection information. Useful when configuring GUI clients.
      db connect   Connect to a database.
      join         Join the active SSH session
      play         Replay the recorded SSH session
      scp          Secure file copy
      ls           List remote SSH nodes
      clusters     List available Teleport clusters
      login        Log in to a cluster and retrieve the session certificate
      logout       Delete a cluster certificate
      status       Display the list of proxy servers and retrieved certificates
      env          Print commands to set Teleport session environment variables
      request ls   List access requests
      request show Show request details
      request new  Create a new access request
      request review Review an access request
      kube ls      Get a list of kubernetes clusters
      kube login   Login to a kubernetes cluster
      kube sessions Get a list of active kubernetes sessions.
      kube exec    Execute a command in a kubernetes pod
      kube join    Join an active Kubernetes session.
      mfa ls       Get a list of registered MFA devices
      mfa add      Add a new MFA device
      mfa rm       Remove a MFA device
      config       Print OpenSSH configuration details

    Try 'tsh help [command]' to get help for a given command.
    ```
### 3.2 TCTL command: tsh help
    ```sh
    root@teleport-demo:~# tctl help
    Usage: tctl [<flags>] <command> [<args> ...]

    CLI Admin tool for the Teleport Auth service. Runs on a host where Teleport Auth is running.

    Flags:
      -d, --debug        Enable verbose logging to stderr
      -c, --config       Path to a configuration file [/etc/teleport.yaml]. Can also be set via the TELEPORT_CONFIG_FILE environment variable.
          --auth-server  Attempts to connect to specific auth/proxy address(es) instead of local auth [127.0.0.1:3025]
      -i, --identity     Path to an identity file. Must be provided to make remote connections to auth. An identity file can be exported with 'tctl auth sign'
          --insecure     When specifying a proxy address in --auth-server, do not verify its TLS certificate. Danger: any data you send can be intercepted or modified by an attacker.

    Commands:
      help         Show help.
      users add    Generate a user invitation token [Teleport DB users only]
      users update Update user account
      users ls     Lists all user accounts.
      users rm     Deletes user accounts
      users reset  Reset user password and generate a new token [Teleport DB users only]
      nodes add    Generate a node invitation token
      nodes ls     List all active SSH nodes within the cluster
      tokens add   Create a invitation token
      tokens rm    Delete/revoke an invitation token
      tokens ls    List node and user invitation tokens
      auth export  Export public cluster (CA) keys to stdout
      auth sign    Create an identity file(s) for a given user
      auth rotate  Rotate certificate authorities in the cluster
      create       Create or update a Teleport resource from a YAML file
      update       Update resource fields
      rm           Delete a resource
      get          Print a YAML declaration of various Teleport resources
      status       Report cluster status
      top          Report diagnostic information
      requests ls  Show active access requests
      requests get Show access request by ID
      requests approve Approve pending access request
      requests deny Deny pending access request
      requests create Create pending access request
      requests rm  Delete an access request
      requests review Review an access request
      apps ls      List all applications registered with the cluster.
      db ls        List all databases registered with the cluster.
      access ls    List all accesses within the cluster.
      lock         Create a new lock.
      bots ls      List all certificate renewal bots registered with the cluster.
      bots add     Add a new certificate renewal bot to the cluster.
      bots rm      Permanently remove a certificate renewal bot from the cluster.
      version      Print cluster version

    Try 'tctl help [command]' to get help for a given command.

    root@teleport-demo:~# 
    ```
### 3.2 TELEPORT command: teleport help

    root@teleport-demo:~# teleport help
    Usage: teleport [<flags>] <command> [<args> ...]

    Clustered SSH service. Learn more at https://goteleport.com/teleport

    Flags:

    Commands:
      help         Show help.
      start        Starts the Teleport service.
      status       Print the status of the current SSH session.
      configure    Generate a simple config file to get started.
      version      Print the version.
      app start    Start application proxy service.
      db start     Start database proxy service.
      db configure create Creates a sample Database Service configuration.
      db configure bootstrap Bootstrap the necessary configuration for the database agent. It reads the provided agent configuration to determine what will be bootstrapped.
      db configure aws print-iam Generate and show IAM policies.
      db configure aws create-iam Generate, create and attach IAM policies.

    Try 'teleport help [command]' to get help for a given command.

    root@teleport-demo:~# 

> Reference address: https://goteleport.com/docs/setup/reference/cli/




