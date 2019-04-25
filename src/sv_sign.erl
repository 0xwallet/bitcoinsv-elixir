-module(sv_sign).
-compile([export_all]).

-define(N, 16#FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141).

%% EVERYTHING is BINARY encoding

priv() ->
    int2bin(16#1AEB4829D9E92290EF35A3812B363B0CA87DFDA2B628060648339E9452BC923A).

%%
%% Crypto Hash functions
%%

sha256(B) ->
    crypto:hash(sha256, B).

hash160(B) ->
    B1 = sha256(B),
    crypto:hash(ripemd160, B1).

hash256(Bin) ->
    sha256(sha256(Bin)).

%% These testcase came from moneybutton/bsv (https://github.com/moneybutton/bsv/blob/master/test/crypto/hash.js)
test_hash() ->
    B = <<0, 1, 2, 3, 253, 254, 255>>,
    <<16#6f2c7b22fd1626998287b3636089087961091de80311b9279c4033ec678a83e8:256/big>> = sha256(B),
    <<16#be586c8b20dee549bdd66018c7a79e2b67bb88b7c7d428fa4c970976d2bec5ba:256/big>> = hash256(B),
    <<16#7322e2bd8535e476c092934e16a6169ca9b707ec:160/big>> = hash160(B).


priv2pub(P) ->
    {Pub, P} = crypto:generate_key(ecdh, secp256k1, P),
    compress_pub(Pub).

compress_pub(<<_:8, X:256, Y:256>>) ->
    Prefix = case Y rem 2 of
        0 -> 2;
        _ -> 3
    end,
    <<Prefix:8, X:256>>.

op_dup() ->
    16#76.

op_hash160() ->
    16#a9.

op_equalverify() ->
    16#88.

op_checksig() ->
    16#ac.

push(B) ->
    [byte_size(B), B].

pub2pkscript(Pub) ->
    Pkhash = hash160(Pub),
    L = [op_dup(), op_hash160(), push(Pkhash), op_equalverify(), op_checksig()],
    iolist_to_binary(L).

version() ->
    <<1:32/little>>.

sequence() ->
    <<16#ffffffff:32/little>>.

locktime() ->
    <<0:32/little>>.

hashtype() ->
    <<16#41:32/little>>.

% [
%   %Bitcoin.Tx.Utxo{
%     hash: <<46, 45, 198, 243, 173, 90, 170, 196, 175, 122, 249, 112, 6, 210, 6,
%       208, 247, 196, 32, 234, 56, 176, 34, 83, 238, 205, 217, 111, 53, 132, 8,
%       26>>,
%     index: 1,
%     script_pubkey: <<118, 169, 20, 146, 111, 145, 91, 215, 40, 85, 134, 174,
%       121, 91, 164, 4, 97, 211, 212, 174, 83, 118, 8, 136, 172>>,
%     value: 12578070
%   }
% ]

len_prefix(B) ->
    S = varint(byte_size(B)),
    <<S/bytes, B/bytes>>.

sign(Priv, Data) ->
    sig_normalize(crypto:sign(ecdsa, sha256, Data, [Priv, secp256k1])).

create_tx() ->
    Priv = priv(),
    Pub = priv2pub(Priv),

    UTxid = int2bin(16#1a0884356fd9cdee5322b038ea20c4f7d006d20670f97aafc4aa5aadf3c62d2e, little),
    UIndex = int32(1),
    UPkscript = int2bin(16#76a914926f915bd7285586ae795ba40461d3d4ae53760888ac),
    UValue = int64(12578070),
    InputCount = varint(1),

    OutputCount = varint(1),
    OValue = int64(12578070 - 300),
    OPkscript = UPkscript,
    OBlock = <<OValue/bytes, (len_prefix(OPkscript))/bytes>>,

    HPreOuts = hash256(<<UTxid/bytes, UIndex/bytes>>),
    HSeq = hash256(sequence()),
    HOuts = hash256(OBlock),

    ToSign = iolist_to_binary([
        version(),
        HPreOuts,
        HSeq,
        UTxid,
        UIndex,
        len_prefix(OPkscript),
        UValue,
        sequence(),
        HOuts,
        locktime(),
        hashtype()
    ]),

    Sig = sign(Priv, ToSign),
    Sig1 = <<Sig/bytes, 16#41>>,

    SigScript = iolist_to_binary([push(Sig1), push(Pub)]),

    IBlock = iolist_to_binary([
        UTxid,
        UIndex,
        len_prefix(SigScript),
        sequence()
    ]),

    Tx = iolist_to_binary([
        version(),
        InputCount,
        IBlock,
        OutputCount,
        OBlock,
        locktime()
    ]),
    bin2hex(Tx).

sig_normalize(<<Type, _, Sig/bytes>>) ->
    <<R_type, R_len, Sig1/bytes>> = Sig,
    <<R:R_len/bytes, Sig2/bytes>> = Sig1,
    <<S_type, S_len, Sig3/bytes>> = Sig2,
    <<S:S_len/bytes, _/bytes>> = Sig3,

    R1 = trim(R),
    S1 = trim(S),
    S2 = low_s(S1),

    R2 = fix_negative(R1),
    S3 = fix_negative(S2),

    LR = byte_size(R2),
    LS = byte_size(S3),
    Len = LR + LS + 4,

    iolist_to_binary([
        Type, Len, R_type, LR, R2, S_type, LS, S3
    ]).

%  Trim leading null bytes
%  But we need to be careful because if the null byte is followed by a byte with 0x80 bit set,
%  removing the null byte would change the number sign.
trim(<<0, B, _Bin/binary>> = Sig) when (B band 16#80) == 16#80 -> Sig;
trim(<<0, Bin/binary>>) -> trim(Bin);
trim(Bin) -> Bin.

fix_negative(<<B, _/binary>> = Bin) when (B band 16#80) == 16#80 -> <<0, Bin/binary>>;
fix_negative(Bin) -> Bin.


%  Ensure that the low S value is used
low_s(S) ->
    S1 = bin2int(S),
    S2 = low_s_num(S1),
    int2bin(S2).

low_s_num(S) when S > ?N/2 -> ?N - S;
low_s_num(S) -> S.




%% HELPERS

int2bin(I) ->
    int2bin(I, big).

int2bin(I, Encoding) ->
    binary:encode_unsigned(I, Encoding).

bin2int(B) -> binary:decode_unsigned(B).

varint(X) when X < 16#fd -> <<X>>;
varint(X) when X =< 16#ffff  -> <<16#fd, X:16/little>>;
varint(X) when X =< 16#ffffffff  -> <<16#fe, X:32/little>>;
varint(X) when X =< 16#ffffffffffffffff  -> <<16#ff, X:64/little>>.

int64(N) ->
    <<N:64/little>>.

int32(N) ->
    <<N:32/little>>.

bin2hex(B) ->
    bin2hex(B, "").

bin2hex(B, D) ->
    string:join([io_lib:format("~2.16.0b", [X]) || <<X>> <= B ], D).

hex2bin(S) ->
    binary:list_to_bin(hex2bin(S, [])).

hex2bin([], R) ->
    lists:reverse(R);

hex2bin([$\  | T], R) ->
    hex2bin(T, R);

hex2bin([A, B | T], R) ->
    hex2bin(T, [digit(A)*16+digit(B)|R]).

digit(X) when X >= $0, X =< $9 ->
    X - $0;

digit(X) when X >= $a, X =< $z ->
    X - $a + 10;

digit(X) when X >= $A, X =< $Z ->
    X - $A + 10.


%% TESTS

test() ->
    test_hash(),

    PUB0 = int2bin(16#024da90ca8bf7861e2bee6931de4588ebba3850a1ad3f05ccd45cad2dd17ba7ae7),
    PKSCRIPT0 = int2bin(16#76a914926f915bd7285586ae795ba40461d3d4ae53760888ac),
    PRIV = priv(),
    PUB = priv2pub(PRIV),
    PKH = hash160(PUB),
    PKSCRIPT = pub2pkscript(PUB),
    %%%%
    PUB = PUB0,
    PKSCRIPT = PKSCRIPT0,
    ok.