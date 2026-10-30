import Foundation
import Testing
import Transactions

struct TokenFixture: Sendable {
    let name: String
    let program: String
    let destination: String
    let createsDestination: Bool
    let amount: UInt64
    let mintData: String
    let sourceData: String
    let destinationData: String
    let wire: String

    func mint(_ encoded: String? = nil) throws -> TokenMint {
        try TokenMint(address: Address(TokenFixtures.mint), owner: Address(program),
                      data: #require(Data(base64Encoded: encoded ?? mintData)))
    }

    func source(_ data: Data? = nil) throws -> TokenAccount {
        try TokenAccount(address: Address(TokenFixtures.source), programOwner: Address(program),
                         data: data ?? #require(Data(base64Encoded: sourceData)))
    }

    func target(_ encoded: String? = nil) throws -> TokenAccount {
        try TokenAccount(address: Address(destination), programOwner: Address(program),
                         data: #require(Data(base64Encoded: encoded ?? destinationData)))
    }
}

enum TokenFixtures {
    static let sender = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
    static let recipient = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    static let mint = "A9ZcnduP9GUGGRLZk9zR2KPGuJnmLCz4Te5umhBKYhpX"
    static let source = "5HHw6ucspj8GLw691ziae7j9grFjcWoS3tmKStMLfGPD"
    static let feeMint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQEAbAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOgDAAAAAAAAGQBkAAAAAAAAADIAAAAAAAAAZAA="
    static let feeSource = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgIACAAAAAAAAAAAAA=="
    static let feeDestination = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgIACAAAAAAAAAAAAA=="
    static let memoAccount = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAggAAQAB"
    static let hookMint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQ4AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOtD91e5AEJueEG4ulOstyuU72UhAE4Du6Cc8Cevm2Q3"
    static let frozenMint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQYAAQAC"
    static let transfers: [TokenFixture] = [
        TokenFixture(
            name: "token existing",
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            destination: "CQif63u3x4S1h3eMoU7YwZXpU1QLX6eCfGzHR7oXfX1B",
            createsDestination: false,
            amount: 1000001,
            mintData: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            sourceData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            destinationData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            wire: "gQEAAg8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEFMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2A/my/GMB4k0Hl68HVkBZ8hEw4PUH4wPUkWDTPeUeuQBKmEBCJhL0bb2VsnqoaXXRVYETxK4c55Bw9zJxFDWE5Sh+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwG3fbh12Whk9nL4UbO63msHLSF7V9bN5E6jPWFfv8AqQAAAAAAAAAAQA0DAAAAAQAEBAoAAQMCAAxBQg8AAAAAAAYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
        TokenFixture(
            name: "token create",
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            destination: "CQif63u3x4S1h3eMoU7YwZXpU1QLX6eCfGzHR7oXfX1B",
            createsDestination: true,
            amount: 18446744073709551615,
            mintData: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            sourceData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            destinationData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            wire: "gQEABQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIIMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2A/my/GMB4k0Hl68HVkBZ8hEw4PUH4wPUkWDTPeUeuQBKmEBCJhL0bb2VsnqoaXXRVYETxK4c55Bw9zJxFDWE5SAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8ofqtYASWqWfywW+gJqkX3YvKRV7Bt7PH8sBtjguaV6cjJclj04kifG7PRApFI4NgwtaE5na/xCEBI572Nvp+FkG3fbh12Whk9nL4UbO63msHLSF7V9bN5E6jPWFfv8AqQAAAAAAAAAAQA0DAAAAAQAGBgEABwQKAAACBAUDBwEBBQIADP//////////BgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
        TokenFixture(
            name: "token2022 existing",
            program: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
            destination: "4isSdV2wfcWt97hFPRj9cCvW4BCkjAipMQvCndmig5h9",
            createsDestination: false,
            amount: 1000001,
            mintData: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            sourceData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            destinationData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            wire: "gQEAAg8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEFMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2A3TOik6VTliGHxhaT/MHM+82CVs4k+Y1RG649bR457UD+bL8YwHiTQeXrwdWQFnyETDg9QfjA9SRYNM95R65AEh+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwG3fbh7nWP3hhCXbzkbM3athr8TYO5DSf+vfko2KGL/AAAAAAAAAAAQA0DAAAAAQAEBAoAAgMBAAxBQg8AAAAAAAYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
        TokenFixture(
            name: "token2022 create",
            program: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
            destination: "4isSdV2wfcWt97hFPRj9cCvW4BCkjAipMQvCndmig5h9",
            createsDestination: true,
            amount: 18446744073709551615,
            mintData: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            sourceData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            destinationData: "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            wire: "gQEABQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIIMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2A3TOik6VTliGHxhaT/MHM+82CVs4k+Y1RG649bR457UD+bL8YwHiTQeXrwdWQFnyETDg9QfjA9SRYNM95R65AEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8ofqtYASWqWfywW+gJqkX3YvKRV7Bt7PH8sBtjguaV6cjJclj04kifG7PRApFI4NgwtaE5na/xCEBI572Nvp+FkG3fbh7nWP3hhCXbzkbM3athr8TYO5DSf+vfko2KGL/AAAAAAAAAAAQA0DAAAAAQAGBgEABwQKAAABBAUDBwECBQEADP//////////BgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
    ]
    static let feeInstructions = [
        "GgEBAAAAAAAAAAYBAAAAAAAAAA==",
        "GgERJwAAAAAAAAYaAAAAAAAAAA==",
        "GgERJwAAAAAAAAYyAAAAAAAAAA==",
        "GgH//////////wYyAAAAAAAAAA==",
    ]
    static let curveSamples: [(encoded: String, onCurve: Bool)] = [
        ("mH5stuTfni+lusWB1rHd5ouzZHcUmHF61hJkQK7d4pA=", false),
        ("QvrEFg87ytRTsb2lrGLV3XQUHgn7T/4ZvjYDYMnNXQM=", false),
        ("ke1hfflNHoQd3n9DOBUrj7Ee0Wbjr4eHYjmSvir9ulE=", false),
        ("6/aWHkfrfXCnQa06Tk1IUd8FQUWbsIbDLgGnlc7gLws=", false),
        ("VW5LsptnrXaiNbdvV6LV7Ypky1mPk+qmR71d45Id6Jg=", false),
        ("XNmzd+6RAvGLuT8cyHAGW/cqCxclSN9XLO0nl+L6IDY=", false),
        ("V+zrB9Yw94ovvNME2p631KBx1eVzEDKUQnGvcKH7VS8=", false),
        ("4MPdyMMt/DOtqC3Phd/7jVML1fM4ilp80G4XD14Kwe8=", true),
        ("ff/ST2xo5ueMsyPACeEMhV3u6gBrWnvHUir1epe+YnQ=", true),
        ("1X/K0OMPDp4rJ5k35iOlSeF983ZfutRSdzHSULhb/y0=", true),
        ("DiQ/6cLsaZBzs8bQQMqMuVqhSGK+iRIKv9xD6ToMtZ4=", false),
        ("5vvbYaj3vT9+akR3oo2iXX43sn7iEBVKJcw6zsL9s8s=", false),
        ("jjfjyHz+JawxYYlZurllYlXRWzdtKlOVM8eqLbTNVo0=", false),
        ("Wzbv36EeBSTS6JrOTaNO1LlSMyXRwRQTHCQONMcFodA=", true),
        ("oZnk9re6ES8oB9R19Y2rG30ibBzmN6Zn9StoZSRcuxg=", false),
        ("g1kr/BJvorNQpUfIO0qL2RRrOIjMe5xFoZa/f898+Tg=", false),
        ("DygO7kmkt2gp6+RtS41wNqatDIrtCTjG4k+uo4CU8sI=", false),
        ("fh1Z1sqIty7hMybg9H1O/RJ+/qLMismOv1QnTdGB57U=", true),
        ("xR7aLZuX6virAytgXb8XyQrK8/OaGpjBRgxwGx6l7LE=", false),
        ("WcTfridreKFff0853M3FoxU11nzHCY1r4IHoa6Kv+PA=", false),
        ("xDrzfflZFwXtcSgN93sL8GK6GxzZROsyWPrZ00XLgl4=", false),
        ("MArYCVGEw6WWT3mGgKL5E18D62EFC7XK0xvGHEq39GA=", true),
        ("jZiIzTm4oT/JY4wWOdaB0oHDBOlMIGwXGWmqVZvKp6o=", true),
        ("RyrUTloDAmhffIDERQY5uZOce3WKWyBjNkY3KeCUnVM=", false),
        ("Qd3GL+zTNT3US9aew2Zkw8OIpKc9PRDGXkJALgoeLoE=", false),
        ("15Zt30pV3POmaApRIasVI8A1kaYlgKXktp+E38FtgNY=", false),
        ("yyvPrp3qAjFDln7Gz+v3yZMunM5oJ7c2kFTt43C5Mhs=", false),
        ("EUK194CZSeLYeTDlMq8QKLr4wtYVWkZAHDhtbMzhR38=", true),
        ("0ggIHKmPP/fPZaAfC1GRwSQX5DvtGQ+kKtm/Pvj7y5k=", true),
        ("2GadfdPoo6JbplsXe5fXbu1pFtDQUESlIqI0pc8Gs54=", true),
        ("hN1zahodQatTNPz+Tsa19/awU382gDqPkPGxWdX0V+k=", false),
        ("9VAyGeX2Uq+hwTBd4QQ+6kUZet+8mrfOnsF8RqN6aos=", false),
        ("EM4NM5h32WPmxlRW92J2MpWvRPvhMyaTt+FGVpC04ts=", true),
        ("0O2TvJPpa/XORA11LRXThr7syJFkFV9v5ztas86IHnI=", true),
        ("aFstagyfuGyTc6nPLbFwizLaYOJM7OpWdvmnKaPNIU4=", true),
        ("uofDl03zPDiia64zTQP8VRavk2P2iKAWnV5KPzcfi0k=", true),
        ("cOaMN8hq6oo1nKwexi9L/QkToyxDNZi+d1rRVXMR+fM=", true),
        ("Fa6PUUR+M7ic5Xg7dLxrLEeN82s0SMYNrU/KTpAi7cY=", true),
        ("vzEGr/TUu18sQ6xTUHGy/kKhSH25+DqDkCzelZJpID0=", true),
        ("t+9Jy6oqHtlCZWnId9+z9zAPNrvrffyWct+Hgx939pk=", true),
        ("u++v3mSmguRHQCX43E9rxSVfK01WmppjX0Uab0eBCL0=", false),
        ("b/tFtEcU8yyt8RQOTWDE7ofnStamxwXaiehbbRit6C8=", true),
        ("tD+6QiADoqQN2mChXP10UPXaJn03gFj2CG55bLRdXXo=", false),
        ("gvhaOk+gHTyFkKM4Hqq2iuGOnF9FELIomMAz3BohRYQ=", true),
        ("oG7Vyi7zA7e8Sewqb8ZZeFZKcpQt8/Z6qiSLs77QLbo=", true),
        ("mMRfl1wQXrCnPC8GHuA/i3CY3DtAT6gIKP5mALhtgH4=", true),
        ("35g6jI1BdRtwOj1IyH+5VXuZCLeSXiiZeNyQZ9mQFeE=", false),
        ("Kk1R4C7IcOpdY3n7InzQYVoaEU/8PirTO9E6H8NvDlE=", false),
        ("K2Tmh47cXOMileOXbtzRYcPLqVuGozOfLEnUb7NoFK0=", true),
        ("gHX8ZklTla7G/GYEy7fCfc5YojIUC2yw3G1bxJTM0No=", false),
        ("gnTW0MOIJ9jKMSm/kL/C1Eti24SYDI80MD/hRN3lhhc=", false),
        ("Tg+MVuN7i3ZXvPolNLnTCC5O8Y3dEF79/EjTg/nKLQU=", true),
        ("1jUe9Lg4TvNiDck2jIGgkRboHfS1h4udhJLzCIpGO5M=", false),
        ("yEkD2JytVeKIwzVYj8+wL6M3JwIC1FHC2OjYxBgL//E=", false),
        ("5uZLIVva2zih28q9RsUtX/Z9OSIRAGPCmPHF1RZnrSE=", false),
        ("d6X06bnT+2XDpmVFMykZDvlIwka0bbVkMVV+AOvum6I=", false),
        ("Ke0HRKQxyFl0BmLE8EIfs21MWz3go6w57NlUVY73Lc8=", false),
        ("fp2t84fv7nkNuoVOzGAttIJZjE4MSNYla6lbT23ZmMs=", false),
        ("kzBDXaMq7cikxOsU/os2K/rWOnm04Mkf7PTpy6gFLco=", false),
        ("0hYz3bPJY145j/XluIA8BmY+mHwnz4sMOIbanqPfvdc=", true),
        ("ftHMo3OLt/U7knPSP93/I2u1DdDjYhI2ShUH9toirCY=", false),
        ("stoLh9pnzbgRWYiZnMdf4wamR4K9cJAuEtqSmbf8PSE=", false),
        ("FD8qD2iZ5NYsqgpJ//T8lwqeiBjn5K8eFp8CMADRHXE=", false),
        ("MRTKMx13jsriUTrR25WKCdIwlHAvsBT8r/w3yMJcYGA=", true),
        ("Ozh++g5uT//+oKCny7GMpGC6tpwRZvccB0du6K3ZsTM=", true),
        ("Myezw1MrhKZXW5YmQgTVPSB5DqyyltKrzHl5YgxcEi0=", false),
        ("AR1OjcujMcg7yTvQaPQnaNC1EhcCocDVBS3jeSx023E=", false),
        ("xfEaMpOUM/eqYTv7RQm65WF+WgBwrMa5wSAtuWmSHY8=", false),
        ("job3mBzdoMicV5R6nI8Cm1npeDMd4jgUFzOXXdavewA=", false),
        ("pS+jlZUbZ9szW+tmpZ/C0WAu8nPrz15hKiGQqoqj8JE=", true),
        ("07lHtXT5QmXIXuhAqAKfmkIE+0YMLTxFfBdcsKIL8wc=", false),
        ("VdE96NsNWb0aMoZVl6WUijrJA/G1SWRCjxK8pmXjJQc=", true),
        ("WGLa+7+nT/fVQeielowGlZEvVds/3URNICsXn6zgi4w=", false),
        ("wR7vk0MLJrHghLInn5LoTa8ni0tl+q83Wid5vALYRYI=", true),
        ("zzijopJ0+0hOTrzVRCet9PY280iIR2nt9ldCdhYDn9M=", false),
        ("cd4w7TGZXXDFZEXvZgTw3hhAitOT0YCpXBP4Q/oc9AQ=", false),
        ("/EcSKp2Rh7NNkeAtOfKk1fseAc32tBLyjUvMQM8rhOI=", true),
        ("Po1wEq5zP6dNQNoYp0no/KIstm88+JBC9OS+LxRXRfY=", false),
        ("toQ/cE9vib+UABMoLfUkcb45ocorAy0V2+BljugaQQs=", true),
        ("FiZycui+dL6mWwRvQ8jXHPiDAf0nNY3g7cUuhRdYiak=", false),
        ("Jho38HJkBp/bky/nMjGxpXPU6uia/tVlVqmj7DzvIh4=", true),
        ("UWdQnQbGj553xR9wFtDsBtisS6Armfpe0AT01P2hcLE=", false),
        ("xznlpTpsVnr3yYWPSp/h6+UaNtGQbxCPt05BC7joSCs=", true),
        ("iWZfEsdtWrujtlSFRXUhOhvrdUpKi8NIKKEkQAE4ttE=", true),
        ("2IoTXeJUIZJ6Ns0Lj2oObmB8Hx4x2gPQzyLtPFui4Lc=", false),
        ("OyitLwe0MnHPrIcs5rVucQ/dXIVGt+tp6u631iKInaI=", true),
        ("si2Oi4ZqtcMIlT+2uVGYi/IYnSu0msS/CNa+gh0f5ak=", true),
        ("WSgn5TAqwE2BNRr8nE6ZOG6SzJZK9QcxGe3d8wCTrAk=", false),
        ("e5by2kU+rLiurvxKNEALZcNti5HDGnx+4frmgOvrvqc=", true),
        ("SUeDhfY8KIRZB7xxEHMDasxqMRIumGcdRzLAHN8yZcw=", false),
        ("phuz/w6WG9TKG5dKxge3TPVnsitVEiHQ52Nle/bNcT8=", true),
        ("NGirvSDEVwgrFCNP+glX/SLnsb4+nWAZjJ30T/42Mgo=", false),
        ("u5j1Ff7Kfm3BD+1gEaAjtIDbKVWwrymXYsmE4kNHVP0=", true),
        ("yDiDUMWncLfYxk0zLKcQzjUYjc42xeVPrBYi3vY/waw=", false),
        ("MQTJCHq1byu29dEMnZ9ZkKcpLwVyp8E9kfTVoMi93uE=", false),
        ("7XJdClDWZ2X0fYSe2uw24GP+MOucRD8RbM9kMhJvVbI=", true),
        ("jhAHCeM0rp/XIXfp9qBOyw94tfVdgEuZpMiOuKGA84I=", true),
        ("1INbyXdCYMUVBkLCjLVanQRh1DDkf6bANSWjG5TGlj4=", true),
        ("oU6uPAMYLW2nk8pSX/g/OHfh1KwJYKaE++wJSNHoYeI=", false),
        ("YuUYQob8PotcWW+FuyBal8gKiP0038XPToGFo9MPfBQ=", false),
        ("czSyhscn3lusweQprc5MLhRt+KoZkVvVV8zOFahcejo=", false),
        ("L40D9zcehp/tFMrcZR2FpGRZce0bYVKb4age06ZWOWs=", false),
        ("kqInIjO91CNe4j8NDMC7pLqm13bA603Gd+3I39coXfY=", false),
        ("OQB3vdnHOVAV8nxkF1Xkb9dKtiwztaqgY9mFX07YVnc=", true),
        ("+a9DPNeAMN0y1z59tSi1bMSXe+p0cfaMrFwoqFOJsBA=", false),
        ("h9pFRBWpsahcs1XaT6Dw6QbPDGrW5Gv4ZyW6U96SVJ4=", false),
        ("DTbDMogsDw1xxDJxEUdAc6WHa89J0aTDUlgi6V8ajxY=", false),
        ("PsieKzeCJVEJY4za658flHhLXzAzLSqlpN8yjnb0EQI=", false),
        ("P2LPFG0+yeDKictSqjvgL1o8/ZzIw74p4N/kghQk+EI=", false),
        ("rMgEBVohT+ykQFj1Ai2DW1h9N3Q1QJfF1gnaiMJS1sI=", true),
        ("+ljo5JZ97XbYjNI31xZDEwsIBhVbmidB5R7BcGbxu1w=", true),
        ("tEuQ9ipF5ScH00E8GCsIrwttW6ETl814JeZMZ0Xfgqg=", false),
        ("OFg5rYjvcKX7bLYRZBHhnmbW8eclwNpQsrc8f31jjx8=", true),
        ("LOjo/uc/Ahefjm5fSpI8ANJgacTBSwbFUbvUk18mgZ8=", false),
        ("zSZvlHRl7HC3s8tYdS6DBla6cT3nUyWAkhYvDcsMfgg=", true),
        ("PGXmMjw2vGcroJrWd287MtsRS2oAHVxrBsMog5c+SlA=", true),
        ("dDBeyKUmvAxouMKkT/G69J61lZNlpMhTpwUnVQpLeqU=", true),
        ("zrD6Evl84yjSqduQ/yH9IxsB1dl/6dYkKMx4V/ogqAc=", true),
        ("CJvO/xTNU+vkaG/MflnWlvMHhN0BNOWPVZnPbBwE11E=", false),
        ("IOSjfTcjmofdBF3Xt6O+WD4tZoaqJrtL9p0UY11QaSM=", true),
        ("ws4UPWLSXJNbHfx83ZyurBA1ApQ8KCWgZ2fpy+DJ0nY=", true),
        ("goF8/pU/RQHpCJSpmYK/kTpdKBTX5i4SvVs0TuBjsTc=", true),
        ("bsVbZKmJexGXaKnlrEgTT+/sjyYgpaAlsMU9y/f0W6A=", true),
        ("6hIWocmdykWd+qdb7+EvTErklHpqhzoB86z0mFN+uro=", false),
        ("LyPH65GiVVoNpHaXjqeW/VWwWbOjFbdygyxdonExyUg=", true),
        ("IVQ2HUAmZiiYPYdd2r/yXQq8HBc7jrWLU3X733BCZ7s=", false),
        ("IzDrC32iYGg8nIacxh96kfhIvxyGFqyVySnT+4/gHaY=", false),
        ("4fu+iWv6cM8PQ584FEGTuxdGUNo/4vRAKRRstR80A8U=", false),
    ]
    static let associatedAccounts: [(owner: String, program: String, expected: String)] = [
        ("BGGnHC4MoSauGS8teUhjLGwUMT8zeea1NA14KreUWeWs", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "AQcTBVxdtBb8p31qka37ffbSCVJe5uBhx7WfYcATjJGs"),
        ("5WTgqCCT8w4E19sX5kqdGD99StuTNpqFqBdQsFPCSxQz", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "9K8sLCuzVrqcWtA8ryrKTWg8sod3o2tvjbTC38LpoKKp"),
        ("Ape4Jh9uTbyHbVBxyvpC1z1uJoEHio9BZzL3npX38cAc", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "97F1Zej8Zqxe25ZwajT3hnJZGZN71UAEDqJwRXcvjgXT"),
        ("Gt6th7nBsDngYcb2EguydeTqLbhuHXGU72mvxfvxs6ga", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "5BBQJprjxnTvsFBcrU6pEUgatkNc2J8vSon3jC71AHMr"),
        ("6kVCd5g9jnExdhoNCpGAQjWkNtz2MDSzFKiriwx6f5e7", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "FmU8NPR7xcPDdDxwcuT3kj3XZDrb1CRLsXN1qemjEZuD"),
        ("7FT3ZNT1RUh4uCbNQYtopsE2rYJkZq9CiVnV6MDxccZb", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "Cp4y6kRvdM7WEEDxXFnSBz8fHXf2uLeX44hTmYyYM3nB"),
        ("6vE15FYEKDuKPpAZnYfG6SNi9x9hSNB1Um3b3SGmFzaa", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "7ZGJV3mVY265mHSTsbDW7eMHzVFsYHQXkkTqLZy6VhYE"),
        ("G8PYsUSNzyfASKGNfLChUyVRDjQptR4VkDUpTPBy3S9C", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "G64PmVvJmELFymZ8oCwCG7Gn7xvnJXQF8YmR4m9TkqCa"),
        ("9UrDJR2VKUkMJvE9KESXa81xGS6UNmfnuXAkCsGPGPw9", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "ENeiiMLUSk1oNudWyBqaAazXxdPs1oaPUQCYF5XBnAFU"),
        ("FNQrs9xWLdQhSS9ANjtJTbFQohPymRVtdxnui3ccweip", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "87N7XfhvKCXoHBsyQCnoiww1cSaEZrKxruC2hMSTHdqE"),
        ("xCmVhd6MZNUCpRAPFcsUbVRvKJkPfWtynTsanFXFdm7", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "4XjPGNGZxZjACoVCE8cHsx3sXfoyRhL5FueQ5otFJRG5"),
        ("GYfWpHZGPXAx36iLGXtagh2QexCw3XVVKN1e1iWMyfTp", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "8uc8a4QnNENsJcqWprGKQCDc3NhXy9XBbBDXw1YxTKNB"),
        ("AaAKhAgUeqWqFjfv2ZC7m3iuitUWyViReJCcaXbqh4H2", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "2uCc3LbQnY1trmsXe3AzuASDmb7sk6wNGwqaMoscnW4H"),
        ("794grHDvocGz1G1NG6Xtx4YxWt8zACMXg9zANahdwXUB", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "6V6RHfoiohNew1HJbLb5LQMc125qnSe7ei7K246WReXX"),
        ("BspkAtMMe4WTsVH7DtrNfsQjTts2APy44T6WmgyMvDAP", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "6hNCDThXTj9BhHZmHhqGpXjS7JxLYCUYN68MoHy8K4ds"),
        ("9qjGoPrSYpfdVbTJ4WKQgFFsVyBGzw6yktmzGav2jUJK", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "5ed6mkHYxN3xVtUyQ9upWtjKGvfKLDvLfcPtdxy92tYa"),
        ("22AYWVkEqJZsNprAtaYzfjuArjoaV6VQ3eyB968gZCYZ", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "FjSgcUsSG3xXgauRaet5J5mYHe5wDpbcKwKZFQ1odkpF"),
        ("9VJL2W5C9jX4Nxac7MpgoE6td6xYDtm6NnsNF7voarKN", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "6bDM4UgbaPvEgScNEcFFC548pH8iuZ7eumxxeRSTAf2m"),
        ("EGUbwKF5ZpBmMEf5ZRtwR6JayMyec1sHvMHikxYQMkR6", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "8uLy1GzAb7F9pWjZXxj29DeLRSApDjWmJpMdYuin36zd"),
        ("73RQGnaG3WUG9tis4achFY2n8qU3kLcutrUsN4V5meXH", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "GhJNC5msDyZoQNif9fFrQMivdVyAVgc2JAUGwXS4JFSj"),
        ("ED13dtfk39qXT5kewTY973SF8vfQ5XdnhCdTRhGwFsiV", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "AVodauxXkj1Db55WoEfrkj67Qqy4cg7t1keHmksL4jda"),
        ("4EYAGrdbWWJCk3HsjEyo1TZ849vKUYPxHMeeRUBxWu1R", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "GLwz1gsRGQ8yNSrv5Jw8u91nXHENwGoTnuS8jdf2q9kZ"),
        ("AXjPUmW3igLU8s1SoNWL2QrMQNAzKwKCYf1uRZYq1D3f", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "6iMibhYMNTyzVk33L5HtfqA6SWFw58NutdaA2JNjkUty"),
        ("5noprLD1biEhGrtqJtQgpgKKHLKTA6sc2aN5J518zkwt", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "FTrteDyJiPzerwtTBAbf3eyeQqrFsLx5J3XxtBU2v2Ty"),
        ("5S7e36ULXNJrZm5GZEXm7vXUg14SKRwWqswuBToWDifr", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "F87f8jnTAdKGGk2KffbBG7EauEKnbY6Qcieq44Cj7iyu"),
        ("FWZhLBCKqHKA3ujkDSNwkjWmt2pVMsyD7iH33kyfmfsj", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "9p6G8memqeDHfz2sUURPZYDdbkACttVdWdLDbYyBGk6a"),
        ("Eg6WZ7DsWGJGM3RRnHCwzGcGYy2YhFgFfodHK8Z2Ziee", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "3Ru177c73svDNDx3Pw3gWM7u3U1UBUPJ7L86tyB5zEPZ"),
        ("2ANvxKi6mCARUdDcefDRprtYWWP2QV9876LVNGuD6UeA", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "9spPppFLaptxjix1hcpzZXuMgTrJ17ybKwvCEwV2FQ8f"),
        ("F8sikPco7qWe42mKo13RPMrWx9jjox1mwz6J4Kz5Sqqr", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "AHBAh6kMrgFCVBHzPJam2Z7HuLrNJNBieJCqRnQ82Az6"),
        ("FZjpLRvRGjcR4TdvEDSZusfCz5eW6vsSAWM7Ad4gorMs", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "3NnBWjAFpddELp2TnuYVhy4HuTY4yYqgdUqEsp23vBQq"),
        ("9wefmKiTQmHiu5A7m2GYPx2exqTbcAzjZD7oy6XfS9C4", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "CMv1BoMNTeMqZUjC3ByZSvBc9s6zE7r5Fr28dG7XarRN"),
        ("HWbp4h4DMzwyQtxgNZAYVyP6EiUQtzTbu7UoJ3kcYesU", "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", "7ZLL7FR6zDQoD4XzrYCsMEMeG12a9wrjw3QNBbSoBsV5"),
    ]
}
