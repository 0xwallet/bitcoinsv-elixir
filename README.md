# BitcoinSV-elixir

本项目基于 [comboy/elixir](https://github.com/comboy/bitcoin-elixir) 修改而来, 正在开发中, 请勿用于生产环境.

# 目录

- [模块结构介绍](#模块结构)
- [网络相关模块](#网络模块)
- [代码测试流程](#代码测试)
- [比特币交易构造](#交易构造)
- [比特币脚本](#比特币脚本)

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

5. 数据结构定义模块

在 elixir 中, 使用 struct 来定义数据结构. 一般地, 结构的名称与其定义所处于的模块名相同. 在模块中看到 "defstruct", 就表明这是一个数据结构定义模块.
----

接下来, 我们将会依照启动的顺序, 为每个模块做详细的介绍:

# 网络模块

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

----

以上, 就是本项目中主要的 "进程定义模块"(Application, GenServer, Supervisor). 接下来的文档是关于其它类型的模块(数据结构定义, 工具函数).

## Bitcoin.Base58Check

**类型:** 工具函数模块.

**介绍:** 比特币地址才用 Base58 编码, 本模块提供了一系列 Base58 编码解码函数.

**APIs:**

- encode/1

        由 binary 格式编码成 Base58 格式.

- decode/1

        将 Base58字符串(普通比特币地址) 解码成 binary 格式.

- decode!/1

        将 Base58字符串(普通比特币地址) 解码成 binary 格式, 解码失败时抛出异常.

- valid?/1

        判断一个字符串是否是合法的 Base58 格式.

- base_encode/1

        由 binary 格式编码成 Base58 格式.(不含 checksum).

- base_decode/1

        将 Base58字符串(普通比特币地址) 解码成 binary 格式(不含 checksum).

- base_decode!/1

        将 Base58字符串(普通比特币地址) 解码成 binary 格式(不含 checksum). 解码失败时抛出异常.

- base_valid?/1

        判断一个字符串是否是合法的 Base58 格式. (不含 checksum).

## Bitcoin.Crypto

封装了一些需要用到的加密函数.

**APIs:**

- ripemd160/1

        哈希160.

- sha1/1

        sha1 哈希.

- sha256/1

        sha256 哈希.




# 代码测试

在本项目中, 包含了大量的测试代码, 以此保证代码的正确运行, 且便于在修改和新增功能的时候, 确保旧的代码没有受到影响.
本项目使用 elixir 通用的测试工具 ExUnit 来进行单元测试. 对于不同类型的模块, 采用的方法也是不同的. 最简单的是工具函数模块, 只需要准备好测试输入以及预期的正确结果, 执行该模块中的工具函数, 判断结果是否正确即可. 这种测试可以被称为无状态测试.

而有一些业务代码涉及到数据库, 进程的启动和终结, 错误处理, 等等具有副作用的函数. 针对这类代码, 测试流程就更为复杂, 需要启动虚拟的数据库(或专门的测试数据库), 或者在测试开始时启动一系列的进程, 在测试结束后关闭进程. 这种测试可以被称为有状态测试.

打开命令行, 在项目根目录下, 运行 "mix test" 即可开始测试.

# 交易构造

比特币的每笔交易, 广播到网络中之后, 矿工会对其进行验证, 验证的步骤包括检查其输入是否存在, 输出的总金额是否小于输入的总金额, 脚本运行是否可以得到 true.

人们常说的验证签名, 其实只是在脚本中包含了验证签名的 opcodes, 如果一个 UTXO(未花费的交易输出) 里没有包含验证签名的 opcodes, 那么是不会进行签名验证的.

比特币脚本类似于 Forth 语言, 是基于双栈的. 脚本执行的结果只有 true 或 false. 在本项目中, 实现了一个比特币脚本的运行时(模块 Bitcoin.Script).

脚本习惯性地被分为两个部分, pk_script 和 sig_script, pk_script 又称锁定脚本, 被放在 output 里. sig_script 又称解锁脚本, 被放在 input 里.

本项目中, 比特币脚本在执行的时候, 需要提供的数据有:

- tx: 完整的交易.
- input_number: 该交易的输入个数.(用于 sighash, 即特殊方法的签名验证)
- sub_script: 同样被用于 sighash, 通常等于 pk_script.
- flags: 脚本验证的选项. (例如 %{p2sh: true, dersig: true})

以下是与交易构造有关的模块:

## bitcoin/protocol/messages/tx.ex 模块名 Bitcoin.Protocol.Messages.Tx

**类型:** 数据结构定义模块.

比特币交易的数据结构定义在此模块中, 有以下几个字段:

- version
- inputs
- outputs
- lock_time

此模块定义了交易的编码和解码函数.

**APIs:**

- parse_stream/1

        将交易从 binary 格式转换为 tx 结构体, 并保留剩余部分.

- parse/1

        将交易从 binary 格式转换为 tx 结构体, 不返回剩余部分

- serialize/1

        将tx 结构体转换为 binary 格式.

## bitcoin/protocol/types/outpoint.ex 模块名 Bitcoin.Protocol.Types.Outpoint

**类型:** 数据结构定义模块.

Outpoint 相当于是交易输出的坐标, 在交易的每个 Input 中都要用到. 它包含以下几个字段:

- hash: 交易的哈希
- index: 此 output 是这笔的第几个 output

**APIs:**

- parse_stream/1

        从 binary 格式转换为 Outpoint 结构体, 并保留剩余部分.

- parse/1

        从 binary 格式转换为 Outpoint 结构体, 不返回剩余部分

- serialize/1

        将 Outpoint 结构体转换为 binary 格式.


## bitcoin/protocol/types/tx_input.ex 模块名 Bitcoin.Protocol.Types.TxInput

**类型:** 数据结构定义模块.

TxInput 表示交易中的输入, 包含以下几个字段:

- previous_output: UTXO, 以 Outpoint 结构体的形式
- signature_script: 解锁脚本.
- swquence: 用于实现"交易替换"功能, 目前未启用

**APIs:**

- parse_stream/1

        从 binary 格式转换为 TxInput 结构体, 并保留剩余部分.

- serialize/1

        将 TxInput 结构体转换为 binary 格式.

## bitcoin/protocol/types/tx_output.ex 模块名 Bitcoin.Protocol.Types.TxOutput

**类型:** 数据结构定义模块.

TxOutput 表示交易中的输出, 包含以下几个字段:

- value: 金额
- pk_script: 锁定脚本

**APIs:**

- parse_stream/1

        从 binary 格式转换为 TxOutput 结构体, 并保留剩余部分.

- serialize/1

        将 TxOutput 结构体转换为 binary 格式.




# 比特币脚本

与脚本执行相关的模块有:

- Bitcoin.Script.Serialization: 将脚本从 binary 格式转换为 opcode list.
- Bitcoin.Script.Control: 用于解析 OP_IF 这类条件语句.
- Bitcoin.Script.Number: 用于编码解码整数(即原始 bitcoin 节点代码中的 CScriptNum).
- Bitcoin.Script.Interpreter: 解释器, 用于运行 OPCODEs.
- Bitcoin.Script.Opcodes: 定义 Opcodes 的名称和值之间的关系.

## bitcoin/script.ex 模块名 Bitcoin.Script

该模块是脚本相关功能的入口.

**APIs:**

- parse/1

        将 binary 格式的脚本转换成类似于 "[:OP_10, :OP_10, :OP_ADD, <<20>>, :OP_EQUAL]" 这样的列表.

- to_bianry/1

        将 opcodes 列表格式的脚本转换成 binary 格式.

- to_string/1

        将 opcodes 列表格式的脚本转换成 bitcoind 兼容的解码后的脚本格式.

- parse_string/1

        将 bitcoind 解码的脚本格式转换为 opcodes 列表的格式.

- parse_string/1

        将测试用例中的格式转换为 opcodes 列表的格式.

- exec/2

        执行给定的脚本, 返回stack.

- verify_sig_pk/2

        分别验证 sig_script 和 pk_script, 返回运行结果的布尔值.

- verify/2

        执行一段脚本, 返回运行结果的布尔值.

- cast_to_bool/1

        将exec 的运行结果变为布尔值.

## bitcoin/script/interpreter.ex 模块名 Bitcoin.Script.Interpreter

**APIs:**

- validate/1

        如果脚本有以下任一情况出现, 则判定其不合法:
        1. 脚本中包含任何已禁用了的操作符;
        2. 超过操作符数量上限(OP_0..OP_16, 以及 OP_RESERVED 不计在内).

- run/3

        运行已变换成 opcode list 格式的脚本.

**一般情况下, 脚本是按顺序执行的, 除了以下特殊情况:**

1. 控制语句(IF, ELSE, NOTIF, ENDIF):

例如 "IF [a] ELSE [b] ENDIF" , 需要在运行之前, 先解析出 [a] 和 [b] 的脚本. 在本项目中, Bitcoin.Script.Control 模块中的 extract 系列函数是专门用于解析此类控制语句的. 步骤如下:

当读取到 IF 操作符时, 对脚本的剩余部分调用 parse_if 函数. 该函数包含这些参数: if_block(即代码块 a), else_block(即代码块 b), script(即剩余脚本), depth(控制语句的嵌套深度).

当 parse_if 函数读取到 ENDIF 操作符, 且嵌套深度为 0 时, 返回 if_block 和 else_block, 以及剩余的 script.

当 parse_if 函数读取到 ELSE 操作符, 且嵌套深度为 0 时, 调用 parse_else 函数.

当 parse_if 函数读取到 IF, NOTIF, ENDIF 中的任意一个, 且嵌套深度不为0 时, 会根据情况改变嵌套深度.

parse_else 的行为与 parse_if 类似, 只是会将操作符读取到 else_block 中.

每次调用 extract 系列函数, 只会解析出一层的控制语句(即 {if_block, else_block, rest_script}), 然后根据条件的真或假来继续调用 run 函数运行 if_block 或者 else_block.

2. 签名验证操作符(CHECKMULTISIG[VERIFY], CHECKSIG[VERIFY]).

这类操作符的运行机制将在 Bitcoin.Tx 模块中详细解释.
