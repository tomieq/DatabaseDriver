//
//  SQLDistinctExpression+Aggregation.swift
//  DatabaseDriver
//
//  Created by: tomieq on 29/05/2026
//

extension SQLDistinctExpression {
    public var count: SQLAggregateExpression<Int> {
        SQLAggregateExpression(sql: "count(\(self.sql))") { value in
            try decodeRequiredScalar(Int.self, from: value)
        }
    }
}

extension SQLDistinctExpression where Value: Comparable & SQLScalarValue {
    public var max: SQLAggregateExpression<Value?> {
        SQLAggregateExpression(sql: "max(\(self.sql))") { value in
            try decodeOptionalScalar(Value.self, from: value)
        }
    }

    public var min: SQLAggregateExpression<Value?> {
        SQLAggregateExpression(sql: "min(\(self.sql))") { value in
            try decodeOptionalScalar(Value.self, from: value)
        }
    }
}

extension SQLDistinctExpression where Value: SQLOptionalValue & Sendable, Value.Wrapped: Comparable & SQLScalarValue {
    public var max: SQLAggregateExpression<Value> {
        SQLAggregateExpression(sql: "max(\(self.sql))") { value in
            try decodeOptionalScalar(Value.Wrapped.self, from: value) as! Value
        }
    }

    public var min: SQLAggregateExpression<Value> {
        SQLAggregateExpression(sql: "min(\(self.sql))") { value in
            try decodeOptionalScalar(Value.Wrapped.self, from: value) as! Value
        }
    }
}

extension SQLDistinctExpression where Value: SQLNumericAggregateValue {
    public var average: SQLAggregateExpression<Double?> {
        SQLAggregateExpression(sql: "avg(\(self.sql))") { value in
            try decodeOptionalScalar(Double.self, from: value)
        }
    }

    public var sum: SQLAggregateExpression<Double?> {
        SQLAggregateExpression(sql: "sum(\(self.sql))") { value in
            try decodeOptionalScalar(Double.self, from: value)
        }
    }

    public var total: SQLAggregateExpression<Double> {
        SQLAggregateExpression(sql: "total(\(self.sql))") { value in
            try decodeOptionalScalar(Double.self, from: value) ?? 0.0
        }
    }
}

extension SQLDistinctExpression where Value: SQLOptionalValue, Value.Wrapped: SQLNumericAggregateValue {
    public var average: SQLAggregateExpression<Double?> {
        SQLAggregateExpression(sql: "avg(\(self.sql))") { value in
            try decodeOptionalScalar(Double.self, from: value)
        }
    }

    public var sum: SQLAggregateExpression<Double?> {
        SQLAggregateExpression(sql: "sum(\(self.sql))") { value in
            try decodeOptionalScalar(Double.self, from: value)
        }
    }

    public var total: SQLAggregateExpression<Double> {
        SQLAggregateExpression(sql: "total(\(self.sql))") { value in
            try decodeOptionalScalar(Double.self, from: value) ?? 0.0
        }
    }
}