"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (_) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
exports.__esModule = true;
exports.calculateOptimalSolution = void 0;
var bn_js_1 = require("bn.js");
exports.calculateOptimalSolution = function (state, orders, weights, calcInvestmentCapacity) { return __awaiter(void 0, void 0, void 0, function () {
    return __generator(this, function (_a) {
        return [2 /*return*/, require('clp-wasm/clp-wasm.all').then(function (clp) {
                var e27 = new bn_js_1(1).mul(new bn_js_1(10).pow(new bn_js_1(27)));
                var maxTinRatio = e27.sub(state.minDropRatio);
                var minTinRatio = e27.sub(state.maxDropRatio);
                var minTINRatioLb = state.maxDropRatio
                    .neg()
                    .mul(state.netAssetValue)
                    .sub(state.maxDropRatio.mul(state.reserve))
                    .add(state.seniorAsset.mul(e27));
                var maxTINRatioLb = state.minDropRatio
                    .mul(state.netAssetValue)
                    .add(state.minDropRatio.mul(state.reserve))
                    .sub(state.seniorAsset.mul(e27));
                var varWeights = [
                    parseFloat(weights.tinInvest.toString()),
                    parseFloat(weights.dropInvest.toString()),
                    parseFloat(weights.tinRedeem.toString()),
                    parseFloat(weights.dropRedeem.toString()),
                ];
                var minTINRatioLbCoeffs = [state.maxDropRatio, minTinRatio.neg(), state.maxDropRatio.neg(), minTinRatio];
                var maxTINRatioLbCoeffs = [state.minDropRatio.neg(), maxTinRatio, state.minDropRatio, maxTinRatio.neg()];
                var lp = "\n      Maximize\n        " + linearExpression(varWeights) + "\n      Subject To\n        reserve: " + linearExpression([1, 1, -1, -1]) + " >= " + state.reserve.neg() + "\n        maxReserve: " + linearExpression([1, 1, -1, -1]) + " <= " + state.maxReserve.sub(state.reserve) + "\n        minTINRatioLb: " + linearExpression(minTINRatioLbCoeffs) + " >= " + minTINRatioLb + "\n        maxTINRatioLb: " + linearExpression(maxTINRatioLbCoeffs) + " >= " + maxTINRatioLb + "\n      Bounds\n        0 <= tinInvest  <= " + orders.tinInvest + "\n        " + (!calcInvestmentCapacity && "0 <= dropInvest <= " + orders.dropInvest) + "\n        0 <= tinRedeem  <= " + orders.tinRedeem + "\n        0 <= dropRedeem <= " + orders.dropRedeem + "\n      End\n    ";
                var output = clp.solve(lp, 0);
                var solutionVector = output.solution.map(function (x) { return new bn_js_1(clp.bnRound(x)); });
                var isFeasible = output.infeasibilityRay.length === 0 && output.integerSolution;
                if (!isFeasible) {
                    // If it's not possible to go into a healthy state, calculate the best possible solution to break the constraints less
                    var currentSeniorRatio = state.seniorAsset.mul(e27).div(state.netAssetValue.add(state.reserve));
                    if (currentSeniorRatio.lte(state.minDropRatio)) {
                        var dropInvest = orders.dropInvest;
                        var tinRedeem = bn_js_1.min(orders.tinRedeem, state.reserve.add(dropInvest));
                        return {
                            dropInvest: dropInvest,
                            tinRedeem: tinRedeem,
                            isFeasible: true,
                            tinInvest: new bn_js_1(0),
                            dropRedeem: new bn_js_1(0)
                        };
                    }
                    if (currentSeniorRatio.gte(state.maxDropRatio)) {
                        var tinInvest = orders.tinInvest;
                        var dropRedeem = bn_js_1.min(orders.dropRedeem, state.reserve.add(tinInvest));
                        return {
                            tinInvest: tinInvest,
                            dropRedeem: dropRedeem,
                            isFeasible: true,
                            dropInvest: new bn_js_1(0),
                            tinRedeem: new bn_js_1(0)
                        };
                    }
                    if (state.reserve.gte(state.maxReserve)) {
                        var dropRedeem = bn_js_1.min(orders.dropRedeem, state.reserve); // Limited either by the order or the reserve
                        var tinRedeem = bn_js_1.min(orders.tinRedeem, state.reserve.sub(dropRedeem)); // Limited either by the order or what's remaining of the reserve after the DROP redemptions
                        return {
                            tinRedeem: tinRedeem,
                            dropRedeem: dropRedeem,
                            isFeasible: true,
                            dropInvest: new bn_js_1(0),
                            tinInvest: new bn_js_1(0)
                        };
                    }
                    return {
                        isFeasible: false,
                        dropInvest: new bn_js_1(0),
                        dropRedeem: new bn_js_1(0),
                        tinInvest: new bn_js_1(0),
                        tinRedeem: new bn_js_1(0)
                    };
                }
                return {
                    isFeasible: isFeasible,
                    dropInvest: solutionVector[1],
                    dropRedeem: solutionVector[3],
                    tinInvest: solutionVector[0],
                    tinRedeem: solutionVector[2]
                };
            })];
    });
}); };
var nameValToStr = function (name, coef, first) {
    var ONE = new bn_js_1(1);
    var ZERO = new bn_js_1(0);
    var coefBN = new bn_js_1(coef);
    if (coefBN.eq(ZERO)) {
        return '';
    }
    var str = '';
    if (first && coefBN.eq(ONE)) {
        return name;
    }
    if (coefBN.eq(ONE)) {
        str += '+';
    }
    else if (coefBN.eq(ONE.neg())) {
        str += '-';
    }
    else {
        str += (coefBN.gt(ZERO) ? '+' : '') + coefBN.toString();
    }
    str += " " + name;
    return str;
};
var linearExpression = function (coefs) {
    var varNames = ['tinInvest', 'dropInvest', 'tinRedeem', 'dropRedeem'];
    var str = '';
    var first = true;
    var n = varNames.length;
    for (var i = 0; i < n; i += 1) {
        str += nameValToStr(varNames[i], coefs[i], first) + " ";
        first = false;
    }
    return str;
};
