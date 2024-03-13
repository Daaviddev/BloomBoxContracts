import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ethers, upgrades } from "hardhat";
import { BloomTiers } from "../typechain";

/**
 * NOT
 * FUNCTIONING
 * YET
 */

// Test template for BloomTiers ERC1155 token once BloomReferral is finished.

describe("BloomTiers ERC1155", function () {
  // Accounts
  let accounts: Signer[];
  let owner: SignerWithAddress;

  // Contracts
  let bloomTiers: BloomTiers, bloomReferral: ;

  const deployContract = async <T extends Contract>(factoryName: string) => {
    const Factory = await ethers.getContractFactory(factoryName);
    const contract = await Factory.deploy();
    await contract.deployed();

    return contract as T;
  };

  beforeEach(async () => {
    [owner, ...accounts] = await ethers.getSigners();

    bloomTiers = await deployContract("Bloom");

    bloomReferral = await deployContract("BloomReferral");
  });

  it("Should successfully mint a Bloom", async () => {
    await bloomTiers.initialize("", bloomReferral.address);

    await bloomTiers.mint(owner.address, 1);

    expect((await bloomTiers.balanceOf(owner.address, 1)).toString() == "1").to.be
      .true;

    await bloomTiers.mint(owner.address, 2);

    expect((await bloomTiers.balanceOf(owner.address, 1)).toString() == "0").to.be
      .true;
    expect((await bloomTiers.balanceOf(owner.address, 2)).toString() == "1").to.be
      .true;

    await bloomTiers.mint(owner.address, 2);
    expect((await bloomTiers.balanceOf(owner.address, 2)).toString() == "1").to.be
      .true;

    await expect(bloomTiers.mint(owner.address, 16)).to.be.revertedWith(
      "Invalid token ID"
    );
  });
});
