pragma solidity 0.5.13;

contract Test1 {

    mapping(uint256 => bytes32) public appHashes;
    mapping(address => bool) validators;
    
    constructor(address[] memory _initValidators) public {
        addValidators(_initValidators);
    }

        
    function testHash(bytes memory bs) public pure returns(bytes32, bytes32) {
        return (sha256(bs), keccak256(bs));
    }
    
    function testLRBits(uint256[] memory prefixes) public pure returns(uint256) {
        uint256 j = 1;
        uint256 acc = 0;
        for (uint256 i = 1; i < prefixes.length; i++) {
            acc += j * ((prefixes[i] >> 255)+1);
            j *= 10;
        }
        return acc;
    }
    
    function toU8Arr(uint256 prefix) public pure returns(bytes memory){
        uint256 n = (prefix >> 248) & 127;
        bytes memory arr = new bytes(n);
        while (n > 0) {
            arr[n-1] = byte(uint8(prefix & 255));
            prefix >>= 8;
            n--;
        }
        return arr;
    }
    
    function getAVLHash(
        uint256[] memory prefixes,
        bytes32[] memory path,
        uint64 key,
        bytes32 valueHash
    ) public pure returns(bytes32) {
        require(prefixes.length == path.length + 1);
        bytes32 leafHash = sha256(abi.encodePacked(
            toU8Arr(prefixes[0]),
            uint8(9),
            uint8(1),
            uint64(key),
            uint8(32),
            valueHash
        ));
        
        for (uint256 i = 1; i < prefixes.length; i++) {
            if (prefixes[i] >> 255 == 1) {
                leafHash = sha256(abi.encodePacked(toU8Arr(prefixes[i]),uint8(32),path[i-1],uint8(32),leafHash));
            } else {
                leafHash = sha256(abi.encodePacked(toU8Arr(prefixes[i]),uint8(32),leafHash,uint8(32),path[i-1]));
            }
        }
        
        return leafHash;
    }
    
    function getAppHash(
        uint256[] memory prefixes,
        bytes32[] memory path,
        bytes32 otherMSHashes,
        uint64 key,
        bytes memory value
    ) public pure returns(bytes32) {
        bytes32 zoracle = sha256(
            abi.encodePacked(
                sha256(
                    abi.encodePacked(getAVLHash(prefixes, path, key, sha256(abi.encodePacked(value))))
                )
            )
        );
        
        return sha256(abi.encodePacked(
            uint8(1),
            otherMSHashes,
            sha256(abi.encodePacked(uint8(0), uint8(7), "zoracle", uint8(32), zoracle))
        ));
    }
    
    function verifyAppHash(
        uint64 blockHeight,
        bytes memory value,
        bytes memory storeProof
    ) public view returns(bool) {
        
        (uint256[] memory prefixes,
        bytes32[] memory path,
        bytes32 otherMSHashes,
        uint64 key) = abi.decode(storeProof, (uint256[], bytes32[], bytes32, uint64));
        
        bytes32 zoracle = sha256(
            abi.encodePacked(
                sha256(
                    abi.encodePacked(getAVLHash(prefixes, path, key, sha256(abi.encodePacked(value))))
                )
            )
        );
        
        return appHashes[blockHeight] == sha256(abi.encodePacked(
            uint8(1),
            otherMSHashes,
            sha256(abi.encodePacked(uint8(0), uint8(7), "zoracle", uint8(32), zoracle))
        ));
    }
    
    function leafHash(bytes memory value) internal pure returns (bytes memory) {
        return abi.encodePacked(sha256(abi.encodePacked(false, value)));
    }
    function innerHash(bytes memory left, bytes memory right) internal pure returns (bytes memory) {
        return abi.encodePacked(sha256(abi.encodePacked(true, left, right)));
    }
    function decodeVarint(bytes memory _encodeByte) public pure returns (uint) {
        uint v = 0;
        for (uint i = 0; i < _encodeByte.length; i++) {
            v = v | uint((uint8(_encodeByte[i]) & 127)) << (i*7);
        }
        return v;
    }
    function addValidators(address[] memory _validators) public {
        for (uint i = 0; i < _validators.length; i++) {
            require(!validators[_validators[i]], "ALREADY_BE_VALIDATOR");
            validators[_validators[i]] = true;
        }
    }
    
    function calculateBlockHash(
        bytes memory _encodedHeight, 
        bytes32 _appHash, 
        bytes32[] memory _others
    ) public pure returns(bytes memory) {
        require(_others.length == 6, "PROOF_SIZE_MUST_BE_6");
        bytes memory left = innerHash(leafHash(_encodedHeight), abi.encodePacked(_others[1]));
        left = innerHash(abi.encodePacked(_others[0]), left);
        left = innerHash(left, abi.encodePacked(_others[2]));
        bytes memory right = innerHash(leafHash(abi.encodePacked(hex"20", _appHash)), abi.encodePacked(_others[4]));
        right = innerHash(right, abi.encodePacked(_others[5]));
        right = innerHash(abi.encodePacked(_others[3]), right);
        return innerHash(left, right);
    }
    
    struct localVar {
        bytes blockHash;
        bytes32 signBytes;
        address signer;
        address lastSigner;
        uint noSig;
    }
    
    function testVerifyAppHash(
        bytes memory value,
        bytes memory storeProof
    ) public pure returns(bytes32) {
        (uint256[] memory prefixes,
        bytes32[] memory path,
        bytes32 otherMSHashes,
        uint64 key) = abi.decode(storeProof, (uint256[], bytes32[], bytes32, uint64));
        
        bytes32 zoracle = sha256(
            abi.encodePacked(
                sha256(
                    abi.encodePacked(getAVLHash(prefixes, path, key, sha256(abi.encodePacked(value))))
                )
            )
        );
        
        return sha256(abi.encodePacked(
            uint8(1),
            otherMSHashes,
            sha256(abi.encodePacked(uint8(0), uint8(7), "zoracle", uint8(32), zoracle))
        ));
    }
    
    function testRecover(bytes32 message, bytes memory _signatures) public pure returns(address[] memory){
        require(_signatures.length % 65 == 0, "INVALID_SIGNATURE_LENGTH");
        uint256 n = _signatures.length / 65;
        bytes32 r;
        bytes32 s;
        uint8 v;
        address[] memory signers = new address[](n);
        for (uint i = 0; i < n; i++) {
            assembly {
                r := mload(add(_signatures, add(mul(65, i), 32)))
                s := mload(add(_signatures, add(mul(65, i), 64)))
                v := and(mload(add(_signatures, add(mul(65, i), 65))), 255)
            }
            if (v < 27) {
                v += 27;
            }
            require(v == 27 || v == 28, "INVALID_SIGNATURE");
            address signer = ecrecover(message, v, r, s);
            signers[i] = signer;
        }
    }

    function submitAppHash(bytes memory appProof) public returns (uint256) {
        (bytes32 _appHash, 
        bytes memory _encodedHeight, 
        bytes32[] memory _others,
        bytes memory _leftMsg,
        bytes memory _rightMsg,
        bytes memory _signatures) = abi.decode(appProof, (bytes32, bytes, bytes32[], bytes, bytes, bytes));
        
        localVar memory vars;
        vars.blockHash = calculateBlockHash(_encodedHeight, _appHash, _others);
        vars.signBytes = sha256(abi.encodePacked(_leftMsg, vars.blockHash, _rightMsg));
        vars.lastSigner = address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        // Verify signature with signBytes
        require(_signatures.length % 65 == 0, "INVALID_SIGNATURE_LENGTH");
        vars.noSig = _signatures.length / 65;
        for (uint i = 0; i < vars.noSig; i++) {
            assembly {
                r := mload(add(_signatures, add(mul(65, i), 32)))
                s := mload(add(_signatures, add(mul(65, i), 64)))
                v := and(mload(add(_signatures, add(mul(65, i), 65))), 255)
            }
            if (v < 27) {
                v += 27;
            }
            require(v == 27 || v == 28, "INVALID_SIGNATURE");
            vars.signer = ecrecover(vars.signBytes, v, r, s);
            require(vars.lastSigner < vars.signer, "SIG_ORDER_INVALID");
            require(validators[vars.signer], "INVALID_VALIDATOR_ADDRESS");
            vars.lastSigner = vars.signer;
        }
        uint256 height = decodeVarint(_encodedHeight);
        appHashes[height] = _appHash;
        return height;
    }
    
    function testSubmitAppHash(
        bytes32 _appHash, 
        bytes memory _encodedHeight, 
        bytes32[] memory _others,
        bytes memory _leftMsg,
        bytes memory _rightMsg,
        bytes memory _signatures
    ) public pure returns(address[] memory) {
        localVar memory vars;
        vars.blockHash = calculateBlockHash(_encodedHeight, _appHash, _others);
        vars.signBytes = sha256(abi.encodePacked(_leftMsg, vars.blockHash, _rightMsg));
        vars.lastSigner = address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        // Verify signature with signBytes
        require(_signatures.length % 65 == 0, "INVALID_SIGNATURE_LENGTH");
        vars.noSig = _signatures.length / 65;
        address[] memory addrs = new address[](vars.noSig);
        for (uint i = 0; i < vars.noSig; i++) {
            assembly {
                r := mload(add(_signatures, add(mul(65, i), 32)))
                s := mload(add(_signatures, add(mul(65, i), 64)))
                v := and(mload(add(_signatures, add(mul(65, i), 65))), 255)
            }
            if (v < 27) {
                v += 27;
            }
            require(v == 27 || v == 28, "INVALID_SIGNATURE");
            vars.signer = ecrecover(vars.signBytes, v, r, s);
            // require(vars.lastSigner < vars.signer, "SIG_ORDER_INVALID");
            // require(validators[vars.signer], "INVALID_VALIDATOR_ADDRESS");
            vars.lastSigner = vars.signer;
            addrs[i] = vars.signer;
        }
        return addrs;
    }
    

    function submitAndVerify (
        bytes calldata data, bytes calldata proof
    ) external returns(bool) {
        (bytes memory appProof, bytes memory storeProof) = abi.decode(proof, (bytes, bytes));

        uint256 height = submitAppHash(appProof);
        require(verifyAppHash(uint64(height), data, storeProof), "FAIL_TO_VERIFY_APP_HASH");
        
        return true;
    }
}
