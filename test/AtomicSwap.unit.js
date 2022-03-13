const { advanceBlockAndSetTime } = require('./helpers/standingTheTime');
const { expect, assert } = require('chai'); 
const { expectRevert, expectEvent, BN } = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');
const { MAX_UINT256 } = require('@openzeppelin/test-helpers/src/constants');
//const { artifacts } = require('hardhat');
const lock = "0x261c74f7dd1ed6a069e18375ab2bee9afcb1095613f53b07de11829ac66cdfcc"; //хэш от ключа
const key = "0x42a990655bffe188c9823a2f914641a32dcbb1b28e8586bd29af291db7dcd4e8"; // ключ


const ERC20Token = artifacts.require("ERC20"); //бинарники sol скомпилирован в байт код для evm.
const AtomicSwap = artifacts.require("AtomicSwapIERC20");

contract('AtomicSwapIERC20', function (accounts) { 
    const [owner, account1, account2] = accounts; //const owner = accounts[0];

    before(async function () { 
        this.token = await ERC20Token.new("DESU", "DESU", { from: owner }); 
        //value - сколько отправить эфира,
        //data - параметры(номер функции и тд)

        await this.token.transfer(account1, web3.utils.toWei("5", "ether"), { from: owner });  
        await this.token.transfer(account2, web3.utils.toWei("5", "ether"), { from: owner });

        this.swap = await AtomicSwap.new({ from: owner });
    });

    describe('method: constructor', async function () {
        it('positive', async function () {
            const swap = await AtomicSwap.new({ from: owner });

            console.log(swap.address);
        });
    });

    describe('method: open', async function () { 
        it('positive', async function () {
            this.token.approve(this.swap.address, web3.utils.toWei("1", "Gwei"), { from: account1 }); //acc1 == msg.sender
            this.token.approve(this.swap.address, web3.utils.toWei("2", "Gwei"), { from: account2 });

            this.AliceValue = web3.utils.toWei("1", "Gwei");
            this.BobValue = web3.utils.toWei("2", "Gwei");

            this.timestamp = (await web3.eth.getBlock('latest')).timestamp;

            const receipt = await this.swap.open(lock, this.AliceValue, this.BobValue, this.token.address, account2, this.token.address, lock, this.timestamp + 1000, { from: account1 });

            await expectEvent(receipt, "Open", {
                _swapID: lock,
                _withdrawTrader: account2,
                _secretLock: lock,
            });//event все выкидывает транзакцию, которая создается
        });

        it('negative', async function () {
            await expectRevert(this.swap.open(lock, this.AliceValue, this.BobValue, this.token.address, account2, this.token.address, lock, this.timestamp + 1000, { from: account1 }),
                "AS: not unique swapID");
        });
    });

    describe('method: close', async function () {
        it('negative', async function () {
            await expectRevert(this.swap.close(lock, lock, { from: account2 }), "AS: incorrect secretKey");
        });

        it('positive', async function () {
            const receipt = await this.swap.close(lock, key, { from: account2 });

            await expectEvent(receipt, "Close", {
                _swapID: lock,
                _secretKey: key,
            });
        });
    });

    describe('method: expire', async function () {
        it('negative', async function () {
            const swap = await AtomicSwap.new({ from: owner });
            await this.token.approve(swap.address, web3.utils.toWei("1", "Gwei"), { from: account1 }); //таким путем мы передаем msg.sender
            await this.token.approve(swap.address, web3.utils.toWei("2", "Gwei"), { from: account2 });

            this.AliceValue = web3.utils.toWei("1", "Gwei"); 
            this.BobValue = web3.utils.toWei("2", "Gwei");
            const timestamp = (await web3.eth.getBlock('latest')).timestamp;

            await swap.open(lock, this.AliceValue, this.BobValue, this.token.address, account2, this.token.address, lock, timestamp + 1000, { from: account1 });
            await advanceBlockAndSetTime(timestamp + 5000);

            await expectRevert(swap.expire(lock, { from: account2 }), "AS: only expired swap");
        });

        it('positive', async function () {
            const swap = await AtomicSwap.new({ from: owner });
            await this.token.approve(swap.address, web3.utils.toWei("1", "Gwei"), { from: account1 }); //таким путем мы передаем msg.sender
            await this.token.approve(swap.address, web3.utils.toWei("2", "Gwei"), { from: account2 });

            this.AliceValue = web3.utils.toWei("1", "Gwei");
            this.BobValue = web3.utils.toWei("2", "Gwei");
            const timestamp = (await web3.eth.getBlock('latest')).timestamp;

            await swap.open(lock, this.AliceValue, this.BobValue, this.token.address, account2, this.token.address, lock, timestamp + 1000, { from: account1 });
            const receipt = await swap.expire(lock, { from: account2 });

            await expectEvent(receipt, "Expire", {
                _swapID: lock,
            });
        });
    });

    describe('method: checkSecretKey', async function () {
        it('negative', async function () {
            await expectRevert(this.swap.checkSecretKey(key, { from: account2 }), "AS: only closed swap"); //No revert reason specified: call expectRevert with the reason string, or use expectRevert.unspecified
            //await expectRevert.unspecified(this.swap.checkSecretKey(lock, {from: account2}, "AS: only closed swap")); //wrong kind of exception received
            //-Given input "AS: only closed swap" is not a number.
        });

        it('positive', async function () {
            const testKey = await this.swap.checkSecretKey(lock, { from: account2 });
            expect(testKey).equal(key);
        });
    });
});

