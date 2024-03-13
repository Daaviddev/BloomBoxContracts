import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { ethers, upgrades } from "hardhat";
import { BloomNFT, BloomsManagerUpgradeable } from "../typechain";

describe("BloomTiers ERC1155", function () {
  // Accounts
  let accounts: Signer[];
  let owner: SignerWithAddress;
  let buyer: SignerWithAddress;

  // Contracts
  let bloomNFT: BloomNFT, bloomNodes: BloomsManagerUpgradeable;

  const deployContract = async <T extends Contract>(factoryName: string) => {
    const Factory = await ethers.getContractFactory(factoryName);
    const contract = await Factory.deploy();
    await contract.deployed();

    return contract as T;
  };

  beforeEach(async () => {
    [owner, buyer, ...accounts] = await ethers.getSigners();

    bloomNFT = await deployContract("BloomNFT");

    bloomNodes = await deployContract("BloomsManagerUpgradeable");
  });

  it("Should successfully mint a BloomNFT", async () => {
    await bloomNFT.initialize(bloomNodes.address, "https://");

    await expect(
      bloomNFT.connect(buyer).mintBloom(buyer.address, 1)
    ).to.be.revertedWith("Not approved");

    await bloomNFT.mintBloom(owner.address, 1);

    expect((await bloomNFT.balanceOf(owner.address)).eq(1)).to.be.true;

    // Disclaimer, minting from bloomNodes has been tested inside bloomManager.test.ts
  });
});
