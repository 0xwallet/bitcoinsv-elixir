# BitcoinSV-elixir

本项目基于 [comboy/elixir](https://github.com/comboy/bitcoin-elixir) 修改而来, 正在开发中, 请勿用于生产环境.

# 主要功能

本项目包含 bitcoinsv 全节点所需的所有功能.

# 模块结构

在 elixir 应用中, 代码通常是按照模块(module)来划分的, 每个模块中包含了某些特定的功能, 例如 "Base58Check" 模块, 就提供了一些关于 Base58 编码的函数.

当程序运行起来后, 模块会被加载到 BEAM VM 中, 就可以对各个模块中的函数进行调用. 最初的调用者通常是我们定义的 Application 进程, 这个进程会以监控树的形式, 逐级地生成子进程. 然后每个进程里面, 会执行各自负责的代码.

一般来说, 一个文件中我们会定义一个模块, 有时一个文件中会定义多个模块. 模块的定义方式是:

```elixir
defmodule Modulename do
    ...
end
```

模块名的格式一般和文件路径是对应的. 例如, "addr.ex" 文件位于路径 "lib/bitcoin/node/network/addr.ex" . 所以在 "addr.ex" 文件中, 我们将模块名定义为 "Bitcoin.Node.Network.Addr".

模块按其代码的功能来分, 大致有以下几类:

1. 工具函数模块:

这种模块中, 只定义了一系列的工具函数, 供其它的进程使用. 例如本项目中的 "Bitcoin.Base58Check" 模块, "Bitcoin.Crypto" 模块.

2. GenServer(通用服务者)模块:

在有的模块中, 会看到 "use GenServer" 这样的代码, 这就意味着, 这个模块是实现了一个通用的服务者. 一般可以通过该模块中的 "start" 函数来启动这个服务者. 在启动之后, 这个服务者进程会一直运行, 接收其它进程发来的消息, 并根据自身状态来回复消息.

在监控树下, GenServer模块是作为 "worker"(工作者) . 本项目中, "Bitcoin.Node.Storage" 模块, "Bitcoin.Node.Inventory" 模块, 都是 GenServer 模块.

3. Supervisor(监控者)模块:

有的模块中, 会看到 "use Supervisor" 这样的代码, 这意味着, 这个模块实现了一个监控者.

在我们的程序运行过程中, 可能会遇到一些意想不到的问题, 导致某个进程崩溃, 这个时候, 就需要对崩溃了的进程进行重启. 在 BEAM VM 里, 通常每个进程都有对应的监控者进程, 监控者进程负责启动, 重启, 关闭它的子进程.

监控者模块也可以被放在监控树下, 形成一个树状的监控结构, 我们以 "supervisor"(监控者) 来标注这些模块. 本项目中, "Bitcoin.Node.Network.Supervisor" 模块, "Bitcoin.Node.Supervisor" 模块, 都是 Supervisor 模块. 注意到, 监控者模块通常以 "Supervisor" 来命名.

4. Application(应用)模块

应用模块是最顶级的模块, 也是 elixir 程序启动之后第一个执行的模块. 在应用模块中, 会看到 "use Application" 这样的代码.

本质上, Application 是一种特殊的 Supervisor, 在应用模块中也需要定义它的子进程. 本项目中的应用模块是 "Bitcoin".

----

接下来, 我们将会依照启动的顺序, 为每个模块做详细的介绍:


## bitcoin.ex 模块名 Bitcoin

**类型:** Application

该文件是启动节点应用时的入口文件, 定义了 Bitcoin Application. 为了方便测试, 我们不会在每次运行 `iex -S mix` (elixir 应用的命令行交互程序)的时候都启动节点. 所以, 要让节点正常启动, 需要在"config/dev.exs" 中配置:

```ex
config :bitcoin, :node,
    modules: [storage_engine: Bitcoin.Node.Storage.Engine.Postgres]
```

这里我们配置的是 storage_engine 的回调模块, 可以是 Postgres 数据库, 也可以是其它的数据库, 只要该模块里实现了节点所需的回调函数即可.

在有了这个配置之后, 在启动程序之后, Bitcoin Application 就会读到此信息, 然后启动节点:

```ex
    # bitcoin.ex

    # Start node only if :bitcoin,:node config section is present
    children = case Application.fetch_env(:bitcoin, :node) do
      :error ->
         []
      {:ok, _node_config} ->
         [ supervisor(Bitcoin.Node.Supervisor, []) ]
    end
```

## bitcoin/node/supervisor.ex 模块名 Bitcoin.Node.Supervisor

**类型:** Supervisor

该文件定义了 bitcoin 节点的最高监控树, Application 进程启动后, 首先启动的就是该监控树.

```ex
    # bitcoin/node/supervisor.ex

    children = [
      worker(Bitcoin.Node, []),
      supervisor(Bitcoin.Node.Network.Supervisor, [])
    ]
```

该监控树下有两个子进程, 一个是 Bitcoin.Node 的 worker(普通进程), 另一个是 Bitcoin.Node.Network.Superviosr(监控树).

当子进程出错崩溃的时候, 监控树会重启子进程.

## bitcoin/node.ex 模块名 Bitcoin.Node

**类型:** GenServer

**职责:**  代表一个在运行的 Bitcoin 节点.

**这个 GenServer 暴露的 API 有:**

- start_link/0

        启动节点进程.

- version_fields/0

        获得本节点的 version 消息.

- config/0

        获得本节点的配置信息.

- nonce/0

        获得本节点所使用的随机数.

- height/0

        本节点的初始区块高度.

- protocol_version/0

        所使用的 p2p 协议的版本.

**该节点启动后的行为是:**

1. 给自己发送 :initialize 消息
```ex
  def init(_) do
    self() |> send(:initialize)
    {:ok, %{}}
  end
```

2. 收到 :initialize 消息后, 从配置文件里读取配置, 并且新建存储区块数据的文件夹(如果区块数据保存在本地的话). 生成之后要使用的随机数 nonce.
```ex
  def handle_info(:initialize, state) do
    Logger.info "Node initialization"

    config = case Application.fetch_env(:bitcoin, :node) do
      :error -> @default_config
      {:ok, config} ->
        @default_config |> Map.merge(config |> Enum.into(%{}))
    end

    File.mkdir_p(config.data_directory)

    state = state|> Map.merge(%{
      nonce: Bitcoin.Util.nonce64(),
      config: config
    })

    {:noreply, state}
  end
```

## bitcoin/node/network/supervisor.ex 模块名 Bitcoin.Node.Network.Supervisor

**类型:** Supervisor

**职责:**  它负责启动和网络有关的进程.

```ex
  def init(_) do
    Logger.info "Starting Node subsystems"

    [
      @modules[:addr],
      @modules[:discovery],
      @modules[:connection_manager],
      # Storage module is an abstraction on top of the actual storage engine so it doesn't have to be dynamic
      Bitcoin.Node.Storage,
      @modules[:inventory]
    ]
    |> Enum.map(fn m -> worker(m, []) end)
    |> supervise(strategy: :one_for_one)
  end
```

它有5个子进程, 是从 @modules 这个模块属性里读取到的, 目前, 根据它会读取到的数据, 这个监控树所有的子进程是:

- Bitcoin.Node.Network.Addr: 负责管理网络中的其它节点的地址
- Bitcoin.Node.Network.Discovery: 负责搜索 DNS, 获得种子节点的地址
- Bitcoin.Node.Network.ConnectionManager: 负责管理与其它节点的连接
- Bitcoin.Node.Storage: 负责存储
- Bitcoin.Node.Inventory: 负责获取缺失的交易或区块信息, 在获取到之后, 广播给其它节点

以上进程全部都是 GenServer.

## bitcoin/node/network/addr.ex 模块名 Bitcoin.Node.Network.Addr

**类型:** GenServer

**职责:**  负责管理网络中的其它节点的地址.

**它暴露出来的 API 有:**

- start_link/0

        启动.

- add/1

        添加新的节点地址.

- get/0

        获取随机的一个节点的地址.

- count/0

        计算已知的节点的数量.

- clear/0

        删除所有的地址.

**它的行为机制是:**

1. 启动后, 过60秒, 给自己发送一个 :periodical_persistance 消息.
2. 收到 :periodical_persistance 消息后, 过60秒, 会再给自己发送一个 :periodical_persistance 消息. 并且删除超出限制的节点地址(目前上限1000个), 并保存剩余的地址到持久存储设备上.

## bitcoin/node/network/discovery.ex 模块名 Bitcoin.Node.Network.Discovery

**类型:** GenServer.

**职责:** 查找种子节点的地址.

**APIs:**

- start_link/0

        启动进程, 并且添加与父进程之间的 link.

> link 的作用是, 子进程崩溃的时候, 会传导到父进程.

- begin_discovery/0

        开始 DNS 搜索.

**行为模式:**

该进程在收到 :begin_discovery 消息之后, 会执行 DNS 搜索策略, 即 "Strategy.DNS.gather_peers/1" . 根据配置中已知的域名, 来搜索 DNS 服务器上的 A 记录, 获取到种子节点的 ip 列表. 然后将这些节点地址发送给负责管理节点地址的进程.

## bitcoin/node/network/connection_manager.ex 模块名 Bitcoin.Node.Network.ConnectionManager

**类型:** GenServer.

**职责:** 管理节点与其它 BSV 节点之间的连接.

**APIs:**

- start_link/0

        启动进程, 并且添加与父进程之间的 link.

- connect(ip, port)

        请求根据 ip 和端口号, 建立 TCP 连接.

- register_peer/0

        由负责与其它节点保持连接的 peer 进程, 向这个 ConnectionManager 进程发送注册请求.

- peers/0

        获取 ConnectionManager 进程所有的 peer 信息.

**行为模式:**

ConnectionManager GenServer 的内部状态有:

- config: 配置信息
- peers: 节点列表

在启动本 GenServer 时, 会使用 "Reagent.start(ReagentHandler, port: port)" 函数来新建 Socket, 然后启动一个 peer 进程, 并将 Socket 移交给 peer 进程.

这里需要重点介绍一下 Reagent. Reagent 是用于实现 Socket 连接池的. 很多情况下, 我们不想实现一个完整的 GenServer 来处理 TCP 连接, 而是仅仅需要一个函数来 handle 连接, 这时候就可以用 reanget 来轻松实现. 在本项目中, 我们的 Bitcoin 节点在连接到区块链网络里之后, 会收到其它节点发来的 TCP 连接请求, 这里使用 Regaent 来处理这些请求.

启动 Reagent 服务, 需要调用 Reagent.start(ReagentHandler, options) , 这里的 ReagentHandler 是我们自己实现的 Reagent 定义, options 里包括端口号等配置信息.

要自定义一个 ReagentHandler, 需要实现 start/0 和 handle/1 这两个函数回调. 采用 "use Reagent" 的时候, 可以省略 start/0 的实现. 在本项目中, 是这样定义 Reagent 的:

```elixir
  # Reagent connection handler
  defmodule ReagentHandler do
    use Reagent
    use Bitcoin.Common

    def handle(%Reagent.Connection{socket: socket}) do
      {:ok, pid} = @modules[:peer].start(socket)
      # Potential issue:
      # If the connection gets closed after Peer.start but before switching the controlling process
      # then probably Peer will never receive _:tcp_closed. Not sure if we need to care because
      # it should just timout then
      socket |> :gen_tcp.controlling_process(pid)
      socket |> :inet.setopts(active: true)
      :ok
    end
  end
```

我们的 Reagent 服务在接收到新的 socket 连接时, 会启动一个专门的 peer 进程, 并将 socket 移交个这个 peer 进程, 然后将这个 socket 设置为 active 状态(所有通过这个 socket 发送来的消息都会被转发给拥有这个 socket 的进程, 这里也就是 peer 进程.).

在 GenServer ConnectionManager 启动之后, 如果配置中没有预先定义好的节点地址列表, 本 GenServer 就会给自己发送一个 :periodical_connectivity_check 消息. 如果有预先定义好的节点, 本 GenServer 就会主动与这些节点建立连接.

在收到 :periodical_connectivity_check 消息时, 首先会给自己发送一个 :check_connectivity 消息, 并且在 10 秒钟之后, 给自己再次发送 :periodical_connectivity_check 消息.

在收到 :check_connectivity 消息时, 会计算当前已知的节点连接数, 如果还未到达上限, 就会调用 add_peer/1 函数, 来添加新的连接.

## bitcoin/node/storage.ex 模块名 Bitcoin.Node.Storage

**类型:** GenServer

**职责:** 区块数据和交易数据的持久化.

**APIs:**

- start_link/1

        启动 GenServer

- store/2

        存储交易或者区块.

- max_height/0

        已知的最大区块高度.

- get_block_with_height/1

        根据高度获取到区块数据.

- store_block/2

        存储区块数据.

- block_height/1

        根据区块数据来得出区块高度.

**行为:**

在 Storage 进程启动时, 首先会启动存储引擎, 例如 PostgreSQL 的客户端进程. 在存储引起启动成功后, 判断一下是否已经有区块数据, 如果没有, 就将创世区块的数据存入存储引擎.

在本项目目前的代码中, Storage GenServer 在存储区块之前, 还要兼具验证区块的工作. 包括每个交易的所有输入是否已经存在, 等等.

## bitcoin/node/inventory.ex 模块名 Bitcoin.Node.Inventory

**类型:** GenServer

**职责:** 从远程节点(peers) 那里获取缺失的数据, 并在验证后广播. 获取到的数据应当被添加到 storage 或者 mempool 中.

**APIs:**

- start_link/1

        启动 GenServer

- seen/1

        其它 peers 看到了新的INV 消息时, 通过调用次函数来向本 GenServer 报告.

- add/1

        将具体的区块数据存储起来.

- request_item/2

        想某个 peer 请求某种数据.

- check_sync/1

        检查本 GenServer 是否处于等待接收区块的状态, 如果不是, 则进行更多的 sync.

- check_orphans/1

        检查本 GenServer 收到的孤块是否已经找到父块. 如以找到, 则将孤块的状态改为 :present.

- block_locator_hashes/0, block_locator_hashes/4

        计算从某个区块回溯得到的这条链的 block_locator_hashes.

        > block_locator 是一系列的区块哈希, 用于描述一条链.从最高的区块开始回溯, 前十个块步长为1, 之后每往前一个块, 步长翻倍.

**行为:**

在 Inventory 进程启动时, 会给自己发送以下两条信息: :periodical_sync 和 :periodical_cleanup.

在收到 :periodical_sync 消息后, Inventory 进程会先给自己发送一个 :sync 消息, 并且在 20 秒后再次给自己发送 :periodical_sync 消息.

在收到 :sync 消息后, 首先判断是否和其它节点有网络连接, 如果有, 则向随机的一个远程节点发送获取区块的请求. 如果没有, 则 10 秒后再次给自己发送 :sync 消息.