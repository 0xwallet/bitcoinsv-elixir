defmodule Bitcoin.Protocol.Types.TxInput do

  alias Bitcoin.Protocol.Types.VarString
  alias Bitcoin.Protocol.Types.Outpoint

  defstruct previous_output: %Outpoint{}, # The previous output transaction reference, as an OutPoint structure
            signature_script: <<>>, # Computational Script for confirming transaction authorization
            sequence: 0 # Transaction version as defined by the sender. Intended for "replacement" of transactions when information is updated before inclusion into a block.

  @type t :: %__MODULE__{
    previous_output: Outpoint.t,
    signature_script: binary,
    sequence: non_neg_integer
  }

  # defimpl Inspect, for: __MODULE__ do
  #   def inspect(data, _opts) do
  #     "%In{ ##{data.sequence} output: #{data.previous_output |> Kernel.inspect}, sig: #{data.signature_script |> Base.encode16} }"
  #   end
  # end

  @spec parse_stream(binary) :: {t, binary}
  def parse_stream(payload) do

    {outpoint, payload} = Outpoint.parse_stream(payload)
    {sig_script, payload} = VarString.parse_stream(payload)
    << sequence :: unsigned-little-integer-size(32), payload :: binary >> = payload

    {%__MODULE__{
      previous_output: outpoint,
      signature_script: sig_script,
      sequence: sequence
    }, payload}

  end

  @spec serialize(t) :: binary
  def serialize(%__MODULE__{} = s) do
    (s.previous_output |> Outpoint.serialize) <>
    (s.signature_script |> VarString.serialize) <>
    << s.sequence ::  unsigned-little-integer-size(32) >>
  end

  @doc """
  Sign a Txinput with private key.
  """
  def sign(%__MODULE__{}, key) do
    #TODO
  end

end
