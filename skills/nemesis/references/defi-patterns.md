# DeFi-Specific Audit Patterns

Reference file for the Nemesis auditor. Load when auditing DeFi protocols, AMMs, lending, staking, or any contract with token accounting.

## Path-Dependent Accumulator Bug — Worked Example

AMM pool with `swap()` that:
1. Calculates amountOut based on reserves
2. Updates accumulatedFees (for LP fee distribution)
3. Updates reserves

**TX1:** Alice swaps 1000 tokenA -> tokenB (0.3% fee)
- fee = 3 tokenA added to accFees BEFORE reserves update
- reserves shift: reserveA=11000, reserveB~9091

**TX2:** Bob swaps 500 tokenA -> tokenB
- fee = 1.5 tokenA added to accFees
- feePerLP calculated using STALE reserve ratio from pre-TX1
- 1 tokenA is now worth LESS in the pool, but fee accounting doesn't know that

**TX3:** Charlie claims LP fees
- Gets paid based on accFees=4.5 at OLD token valuation
- Pool composition has shifted — fees are denominated in a token whose relative value changed
- Result: early LPs overpaid, late LPs underpaid

**Root cause:** accFees accumulator doesn't rebase against current reserve ratio. Each swap changes what "1 unit of fee" means, but the accumulator treats all units as equal.

**Generalization:** Any global accumulator (fees, rewards, interest) updated per-tx where the VALUE of what's accumulated changes between txs, and the accumulator doesn't normalize.

**Verification check:** After N operations with varying sizes, does SUM(individual fees) == fee on AGGREGATE operation? If not: path-dependent accumulator, exploitable.

## DeFi-Specific Adversarial Sequences

These patterns exploit the gap between "operation that changes accounting base" and "operation that reads the accounting":

- **Swap with value X -> swap with value Y -> claim fees** — fee accumulator path-dependent?
- **Deposit -> partial withdraw -> claim rewards** — rewards computed on which balance? old or new?
- **Stake -> unstake half -> restake -> unstake all** — reward debt accumulated correctly through each step?
- **Open position -> add collateral -> partial close -> health check** — cached health factor updated at each step?
- **Provide liquidity -> swaps happen -> remove liquidity** — fee tracking correct through reserve changes?
- **Delegate votes -> transfer tokens -> vote** — voting power reflects current balance?
- **Borrow -> partial repay -> borrow again -> check debt** — interest accumulator rebased at each step?

## Common DeFi Coupled State Patterns

These are the most frequent sources of state inconsistency bugs in DeFi:

| Pattern | State A | State B (coupled) | Common gap |
|---------|---------|-------------------|------------|
| Staking rewards | user stake balance | rewardDebt / rewardPerTokenPaid | partial unstake doesn't update debt |
| LP accounting | LP token supply | reserve0 / reserve1 | burn path vs transfer path diverge |
| Lending health | collateral amount | borrowedAmount / healthFactor | liquidation path skips health recalc |
| Governance | token balance | voting power / delegation | transfer doesn't update delegatee |
| Vesting | vested amount | claimed amount / cliff state | early termination leaves stale claims |
