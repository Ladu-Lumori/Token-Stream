import {
  Cl,
  createStacksPrivateKey,
  cvToValue,
  signMessageHashRsv,
} from "@stacks/transactions";
import { beforeEach, describe, expect, it } from "vitest";

// `simnet` is a "simulation network" - a local, testing Stacks node for running our tests
const accounts = simnet.getAccounts();

// The identifiers of these wallets can be found in the `settings/Devnet.toml` config file
// You can also change the identifiers of these wallets in those files if you want
const sender = accounts.get("wallet_1")!;
const recepient = accounts.get("wallet_2")!;
const randomUser = accounts.get("wallet_3")!;

describe("test token streaming contract", () => {
  // Before each test is run, we want to create a stream
  // so we can run tests around different possible things to do with the stream
  beforeEach(() => {
    const result = simnet.callPublicFn(
      "stream",
      "stream-to",
      [
        Cl.principal(recepient),
        Cl.uint(5),
        Cl.tuple({ "start-block": Cl.uint(0), "end-block": Cl.uint(5) }),
        Cl.uint(1),
      ],
      sender
    );

    expect(result.events[0].event).toBe("stx_transfer_event");
    expect(result.events[0].data.amount).toBe("5");
    expect(result.events[0].data.sender).toBe(sender);
  });

  it("ensures contract is initialized properly and stream is created", () => {
    const latestStreamId = simnet.getDataVar("stream", "latest-stream-id");
    expect(latestStreamId).toBeUint(1);

    const createdStream = simnet.getMapEntry("stream", "streams", Cl.uint(0));
    expect(createdStream).toBeSome(
      Cl.tuple({
        sender: Cl.principal(sender),
        recepient: Cl.principal(recepient),
        balance: Cl.uint(5),
        "withdrawn-balance": Cl.uint(0),
        "payment-per-block": Cl.uint(1),
        timeframe: Cl.tuple({
          "start-block": Cl.uint(0),
          "end-block": Cl.uint(5),
        }),
      })
    );
  });

  it("ensures stream can be refueled", () => {
    const result = simnet.callPublicFn(
      "stream",
      "refuel",
      [Cl.uint(0), Cl.uint(5)],
      sender
    );

    expect(result.events[0].event).toBe("stx_transfer_event");
    expect(result.events[0].data.amount).toBe("5");
    expect(result.events[0].data.sender).toBe(sender);

    const createdStream = simnet.getMapEntry("stream", "streams", Cl.uint(0));
    expect(createdStream).toBeSome(
      Cl.tuple({
        sender: Cl.principal(sender),
        recepient: Cl.principal(recepient),
        balance: Cl.uint(10),
        "withdrawn-balance": Cl.uint(0),
        "payment-per-block": Cl.uint(1),
        timeframe: Cl.tuple({
          "start-block": Cl.uint(0),
          "end-block": Cl.uint(5),
        }),
      })
    );
  });

  it("ensures stream cannot be refueled by random address", () => {
    const result = simnet.callPublicFn(
      "stream",
      "refuel",
      [Cl.uint(0), Cl.uint(5)],
      randomUser
    );

    expect(result.result).toBeErr(Cl.uint(0));
  });

  it("ensures recepient can withdraw tokens over time", () => {
    // Block 1 was used to deploy contract
    // Block 2 was used to create stream
    // `withdraw` will be called in Block 3
    // so expected to withdraw (Block 3 - Start_Block) = (3 - 0) tokens
    const withdraw = simnet.callPublicFn(
      "stream",
      "withdraw",
      [Cl.uint(0)],
      recepient
    );

    expect(withdraw.events[0].event).toBe("stx_transfer_event");
    expect(withdraw.events[0].data.amount).toBe("3");
    expect(withdraw.events[0].data.recepient).toBe(recepient);
  });

  it("ensures non-recepient cannot withdraw tokens from stream", () => {
    const withdraw = simnet.callPublicFn(
      "stream",
      "withdraw",
      [Cl.uint(0)],
      randomUser
    );

    expect(withdraw.result).toBeErr(Cl.uint(0));
  });

  it("ensures sender can withdraw excess tokens", () => {
    // Block 3
    simnet.callPublicFn("stream", "refuel", [Cl.uint(0), Cl.uint(5)], sender);

    // Block 4 and 5
    simnet.mineEmptyBlock();
    simnet.mineEmptyBlock();

    // Claim tokens
    simnet.callPublicFn("stream", "withdraw", [Cl.uint(0)], recepient);

    // Withdraw excess
    const refund = simnet.callPublicFn(
      "stream",
      "refund",
      [Cl.uint(0)],
      sender
    );

    expect(refund.events[0].event).toBe("stx_transfer_event");
    expect(refund.events[0].data.amount).toBe("5");
    expect(refund.events[0].data.recepient).toBe(sender);
  });

  it("signature verification can be done on stream hashes", () => {
    const hashedStream0 = simnet.callReadOnlyFn(
      "stream",
      "hash-stream",
      [
        Cl.uint(0),
        Cl.uint(0),
        Cl.tuple({ "start-block": Cl.uint(1), "end-block": Cl.uint(2) }),
      ],
      sender
    );
    console.log(hashedStream0.result);

    const hashAsHex = Buffer.from(hashedStream0.result.type).toString("hex");
    const signature = signMessageHashRsv({
      messageHash: hashAsHex,
      privateKey: createStacksPrivateKey(
        "7287ba251d44a4d3fd9276c88ce34c5c52a038955511cccaf77e61068649c17801"
      ),
    });
    console.log(signature);

    const verifySignature = simnet.callReadOnlyFn(
      "stream",
      "validate-signature",
      [
        Cl.buffer(hashedStream0.result.buffer),
        Cl.bufferFromHex(signature.data),
        Cl.principal(sender),
      ],
      sender
    );

    expect(cvToValue(verifySignature.result)).toBe(true);
  });

  it("ensures timeframe and payment per block can be modified with consent of both parties", () => {
    const hashedStream0 = simnet.callReadOnlyFn(
      "stream",
      "hash-stream",
      [
        Cl.uint(0),
        Cl.uint(1),
        Cl.tuple({ "start-block": Cl.uint(0), "end-block": Cl.uint(4) }),
      ],
      sender
    );
    console.log(hashedStream0.result);

    const hashAsHex = Buffer.from(hashedStream0.result.buffer).toString("hex");
    const senderSignature = signMessageHashRsv({
      messageHash: hashAsHex,
      // This private key is for the `sender` wallet - i.e. `wallet_1`
      // This can be found in the `settings/Devnet.toml` config file
      privateKey: createStacksPrivateKey(
        "7287ba251d44a4d3fd9276c88ce34c5c52a038955511cccaf77e61068649c17801"
      ),
    });
    console.log(senderSignature);

    simnet.callPublicFn(
      "stream",
      "update-details",
      [
        Cl.uint(0),
        Cl.uint(1),
        Cl.tuple({ "start-block": Cl.uint(0), "end-block": Cl.uint(4) }),
        Cl.principal(sender),
        Cl.bufferFromHex(senderSignature.data),
      ],
      recepient
    );

    const updatedStream = simnet.getMapEntry("stream", "streams", Cl.uint(0));
    expect(updatedStream).toBeSome(
      Cl.tuple({
        sender: Cl.principal(sender),
        recepient: Cl.principal(recepient),
        balance: Cl.uint(5),
        "withdrawn-balance": Cl.uint(0),
        "payment-per-block": Cl.uint(1),
        timeframe: Cl.tuple({
          "start-block": Cl.uint(0),
          "end-block": Cl.uint(4),
        }),
      })
    );
  });
});