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

该进程是一个 GenServer(通用微服务进程), 代表一个在运行的 Bitcoin 节点.

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

这是一个监控树, 它负责启动和网络有关的进程.

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

该 GenServer 负责负责管理网络中的其它节点的地址.

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

在启动本 GenServer 时, 会使用 "Reagent.start(ReagnetHandler, port: port)" 函数来新建 Socket, 然后启动一个 peer 进程, 并将 Socket 移交给 peer 进程.