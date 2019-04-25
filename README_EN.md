# bitcoinsv-elixir

Since bitcoin SV network has started, we need a cloud wallet server which can address the need for mainstream users, especially for business / organization / merchants who wants to be connected to the MetaNet. which is an important platform for the future 
IoV (Internet of Value). The core difference between classical internet and MetaNet is the additional blockchain layer on top of TCPIP. since many important feature requires a bitcoin node for operations on addresses, signatures, transactions and scripts, 
we need a flexiable and high performance node implementation for billions of users (humans & machines).      

## Current status

* Full protocol parser and serialization
* Script interpreter of Whitepaper  
* Connecting and accepting connections from other peers
* Syncing blockchain into a postgres database 
* SPV mode with 3rd Party API
* Configurable modules (you can plug in your own peer handler, connection manager, storage engine etc.)


## Roadmap

* Storage properly handling reorgs and optimizations 
* Mempool with 0-conf and double spending detection
* Tokenized Smart Contract Service
* Allow it to run across multiple nodes



## Usage

- Setup & Install
    - Elixir
    - Database
    - Config File
- CLI operations
    - Check balance of an address 
    - Send Bitcoin to an address with optional fees
- Dashboard API
    - User deposit status API
    - User withdraw status API 
    - Transaction signing with Cold Wallet 




## Running the node

To start a node uncomment the following line in the dev.exs

    # config :bitcoin, :node, []

To avoid abusing the network you may want to only connect to your local node e.g.:

    config :bitcoin, :node, [
      connect: [{127,0,0,1}]
    ]

Check (config.exs)[config/config.exs] for more details.

## License

See the LICENSE file in the project root.

## Contributing

Please fork this repository to your own account, create a feature/{short but descriptive name} branch on your own repository and submit a pull request back to develop.

Any kind of contributions are super welcome. commercial developer please contact OWAF for Full Documentation and Membership. 


