const solver = require('./solver.js');
const BN = require('bn.js');
const problem = require('./problems/invest_order.json');

const e27 = new BN(1).mul(new BN(10).pow(new BN(27)))
const objToNum = (jsonNumber) => {
  if (typeof jsonNumber == 'string') return new BN(jsonNumber)
  const add = jsonNumber.add ? jsonNumber.add : 0
  return new BN(jsonNumber.value * 100000).mul(new BN(10).pow(new BN(jsonNumber.base - 5))).add(new BN(add))
}

const args = process.argv.slice(2);

if(args.length != 10) {
  console.log(`please supply the correct parameters:

    1.  dropInvest
    2.  dropRedeem
    3.  tinInvest
    4.  tinRedeem

    5.  netAssetValue
    6.  reserve
    7.  seniorAsset
    8.  minDropRatio
    9.  maxDropRatio
    10. maxReserve

  `)
  process.exit(1);
} 

const dropInvest    = new BN(process.argv[2])
const dropRedeem    = new BN(process.argv[3])
const tinInvest     = new BN(process.argv[4])
const tinRedeem     = new BN(process.argv[5])
             
const netAssetValue = new BN(process.argv[6])
const reserve       = new BN(process.argv[7])
const seniorAsset   = new BN(process.argv[8])
const minDropRatio  = new BN(process.argv[9])
const maxDropRatio  = new BN(process.argv[10])
const maxReserve    = new BN(process.argv[11])

// console.log(objToNum(problem.orders.dropInvest).toString())
// console.log(objToNum(problem.orders.dropRedeem).toString())
// console.log(objToNum(problem.orders.tinInvest).toString())
// console.log(objToNum(problem.orders.tinRedeem).toString())
//
// console.log(objToNum(problem.state.netAssetValue).toString())
// console.log(objToNum(problem.state.reserve).toString())
// console.log(objToNum(problem.state.seniorAsset).toString())
// console.log(e27.sub(objToNum(problem.state.maxTinRatio)).toString())
// console.log(e27.sub(objToNum(problem.state.minTinRatio)).toString())
// console.log(objToNum(problem.state.maxReserve).toString())


const orders = {
    dropInvest,
    dropRedeem,
    tinInvest,
    tinRedeem
}

const state = {
    netAssetValue,
    reserve,
    seniorAsset,
    minDropRatio,
    maxDropRatio,
    maxReserve
}

const weights = {
  dropRedeem: new BN(1000000),
  tinRedeem: new BN(100000),
  tinInvest: new BN(10000),
  dropInvest: new BN(1000)
}


;(async () => {
    const fill = x => "0".repeat(64 - x.length) + x
    const r = await solver.calculateOptimalSolution(state, orders, weights)
    const isFeasible = fill(r.isFeasible ? "1" : 0);
    const dropInvest = fill(r.dropInvest.toString('hex'));
    const dropRedeem = fill(r.dropRedeem.toString('hex'));
    const tinInvest  = fill(r.tinInvest.toString('hex'));
    const tinRedeem  = fill(r.tinRedeem.toString('hex'));
    process.stdout.write("0x" + [isFeasible, dropInvest, dropRedeem, tinInvest, tinRedeem].join(""))
})()
