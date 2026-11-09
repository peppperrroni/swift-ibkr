import Foundation

func body(_ fields: String...) -> [UInt8] { fields.flatMap { Array($0.utf8) + [0] } }

func d(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }
