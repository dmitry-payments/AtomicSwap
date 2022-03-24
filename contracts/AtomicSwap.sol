pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract AtomicSwapIERC20 {
    struct Swap {
        uint256 timelock;
        uint256 IERC20AliceValue;
        uint256 IERC20BobValue;
        address Alice; 
        address IERC20AliceContract;
        address IERC20BobContract; 
        address Bob; 
        bytes32 secretLock;
        bytes secretKey;
    }

    enum States {
        INVALID,
        OPEN,
        CLOSED,
        EXPIRED
    }

    mapping (bytes32 => Swap) private swaps;
    mapping (bytes32 => States) private swapStates;

    event Open(bytes32 _swapID, address _withdrawTrader, bytes32 _secretLock); //выброс логов
    event Expire(bytes32 _swapID);
    event Close(bytes32 _swapID, bytes _secretKey);

    modifier onlyInvalidSwaps(bytes32 _swapID) {
        require(swapStates[_swapID] == States.INVALID, "AS: not unique swapID");
        _;
    }

    modifier onlyOpenSwaps(bytes32 _swapID) {
        require(swapStates[_swapID] == States.OPEN, "AS: only open swap");
        _;
    }

    modifier onlyClosedSwaps(bytes32 _swapID) {
        require(swapStates[_swapID] == States.CLOSED, "AS: only closed swap");
        _;
    }

    modifier onlyExpirableSwaps(bytes32 _swapID) {
        require(swaps[_swapID].timelock >= block.timestamp, "AS: only expired swap");
        _;
    }

    modifier onlyWithSecretKey(bytes32 _swapID, bytes memory _secretKey) {
        // TODO: Require _secretKey length to conform to the spec
        require(swaps[_swapID].secretLock == sha256(_secretKey), "AS: incorrect secretKey");
        _;
    }

    function open(bytes32 _swapID, uint256 _IERC20AliceValue, uint256 _IERC20BobValue, address _IERC20AliceContract, address _bob, 
                    address _IERC20BobContract, bytes32 _secretLock, uint256 _timelock) public onlyInvalidSwaps(_swapID) {

        //require(swapStates[_swapID] == States.INVALID);//проверка на то что свап ИД уникальный
        // Transfer value from the IERC20 trader to this contract.
        IERC20 IERC20AliceInstance = IERC20(_IERC20AliceContract); //IERC20AliceContract - инстанс
        require(IERC20AliceInstance.transferFrom(msg.sender, address(this), _IERC20AliceValue), "AS: ERC20 transferFrom error");// изымаются деньги у алисы на счет атомикс свопа
        
        IERC20 IERC20BobInstance = IERC20(_IERC20BobContract);
        require(IERC20BobInstance.transferFrom(_bob, address(this), _IERC20BobValue), "AS: ERC20 transferFrom error");
        //secretLock - хэш от секретного ключа, секретный ключ создает БОБ! 
        //timelock - окончательное время сделки.

        // Store the details of the swap. Забивается структурка. ({})
        Swap memory swap = Swap({
            timelock: _timelock,
            IERC20AliceValue: _IERC20AliceValue,
            IERC20BobValue: _IERC20BobValue,
            Alice: msg.sender, //здесь это адрес алисы
            IERC20AliceContract: _IERC20AliceContract,
            IERC20BobContract: _IERC20BobContract,
            Bob: _bob,
            secretLock: _secretLock,
            secretKey: new bytes(0)
        });
        swaps[_swapID] = swap;
        swapStates[_swapID] = States.OPEN;
        emit Open(_swapID, _bob, _secretLock);//эвент отправляется в транзакцию, которую видит весь блокчейн,
        //и таким образом любой может !попытаться! вызвать epxpire (сорвать сделку)
    }

    function close(bytes32 _swapID, bytes memory _secretKey) public onlyOpenSwaps(_swapID)//вызывает БОБ. Передает туда полноценный секретный ключ, а не хэш.
        onlyWithSecretKey(_swapID, _secretKey) {

        // Close the swap.
        Swap memory swap = swaps[_swapID];
        swaps[_swapID].secretKey = _secretKey;
        swapStates[_swapID] = States.CLOSED;

        // Transfer the IERC20 funds from this contract to the withdrawing trader.
        IERC20 IERC20AliceInstance = IERC20(swap.IERC20AliceContract); //IERC20AliceContract - инстанс
        require(IERC20AliceInstance.transfer(swap.Bob,swap.IERC20AliceValue));
        
        IERC20 IERC20BobInstance = IERC20(swap.IERC20BobContract);
        require(IERC20BobInstance.transfer(swap.Alice, swap.IERC20BobValue));

        emit Close(_swapID, _secretKey);
    }

    function expire(bytes32 _swapID) public onlyOpenSwaps(_swapID) onlyExpirableSwaps(_swapID) {
        Swap memory swap = swaps[_swapID];
        require(swap.Alice == msg.sender || swap.Bob == msg.sender, "Error");
        swapStates[_swapID] = States.EXPIRED;

        IERC20 IERC20AliceInstance = IERC20(swap.IERC20AliceContract); //инстанс
        require(IERC20AliceInstance.transfer(swap.Alice, swap.IERC20AliceValue));
        
        IERC20 IERC20BobInstance = IERC20(swap.IERC20BobContract);
        require(IERC20BobInstance.transfer(swap.Bob, swap.IERC20BobValue));

        emit Expire(_swapID);
    }

    function check(bytes32 _swapID) public view returns (uint256, uint256, //обычно вызывает БОБ, возвращается структура данных которую мы вызываем в open
        address, address, bytes32) {
        Swap memory swap = swaps[_swapID];
        return (swap.timelock, swap.IERC20AliceValue, swap.IERC20AliceContract, swap.Bob, swap.secretLock);
    }

    function checkSecretKey(bytes32 _swapID) public view onlyClosedSwaps(_swapID) returns (bytes memory secretKey) {
        Swap memory swap = swaps[_swapID];
        return swap.secretKey;
    } //вернет секретный ключ когда сделка завершена, и нули пока сделка не завершена
}
