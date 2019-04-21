# BitcoinSV-elixir

本项目基于 [comboy/elixir](https://github.com/comboy/bitcoin-elixir) 修改而来, 正在开发中, 请勿用于生产环境.

# 主要功能

本项目包含 bitcoinsv 全节点所需的所有功能.

# 模块结构

## bitcoin.ex

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

## bitcoin/node/supervisor.ex

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

## bitcoin/node.ex

该进程是一个 GenServer(通用微服务进程), 代表一个在运行的 Bitcoin 节点.

- 这个 GenServer 暴露的 API 有:

### start_link/0

启动节点进程.

### version_fields/0

获得本节点的 version 消息.

### config/0

获得本节点的配置信息.

### nonce/0

获得本节点所使用的随机数.

### height/0

本节点的初始区块高度.

### protocol_version/0

所使用的 p2p 协议的版本.

- 该节点启动后的行为是:

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

## bitcoin/node/network/supervisor.ex

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

## bitcoin/node/network/addr.ex

该 GenServer 负责负责管理网络中的其它节点的地址.

- 它暴露出来的 API 有:

### start_link/0

启动.

### add/1

添加新的节点地址.

### get/0

获取随机的一个节点的地址.

### count/0

计算已知的节点的数量.

### clear/0

删除所有的地址.

- 它的行为机制是:

1. 启动后, 过60秒, 给自己发送一个 :periodical_persistance 消息.
2. 收到 :periodical_persistance 消息后, 过60秒, 会再给自己发送一个 :periodical_persistance 消息. 并且删除超出限制的节点地址(目前上限1000个), 并保存剩余的地址到持久存储设备上.

